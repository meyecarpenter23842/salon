import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'lan_contract.dart';
import 'lan_pairing.dart';

class LanHostConfig {
  LanHostConfig({
    required this.address,
    required this.port,
    required this.certificatePath,
    required this.privateKeyPath,
  }) {
    final bytes = address.rawAddress;
    final privateV4 = address.type == InternetAddressType.IPv4 &&
        (address.isLoopback ||
            bytes[0] == 10 ||
            (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
            (bytes[0] == 192 && bytes[1] == 168));
    if (!privateV4 || port < 1 || port > 65535) {
      throw const FormatException('Invalid LAN address or port');
    }
  }

  factory LanHostConfig.fromJson(Map<String, dynamic> json) {
    if (json['address'] is! String ||
        json['port'] is! int ||
        json['certificatePath'] is! String ||
        json['privateKeyPath'] is! String) {
      throw const FormatException('Invalid LAN configuration');
    }
    return LanHostConfig(
      address: InternetAddress(json['address'] as String),
      port: json['port'] as int,
      certificatePath: json['certificatePath'] as String,
      privateKeyPath: json['privateKeyPath'] as String,
    );
  }

  final InternetAddress address;
  final int port;
  final String certificatePath;
  final String privateKeyPath;

  Uri get apiUrl => Uri(
    scheme: 'https',
    host: address.address,
    port: port,
    path: LanContract.basePath,
  );

  /// Fingerprint of the first (server) certificate, never of PEM text or key.
  Future<String> certificateSha256() async {
    final pem = await File(certificatePath).readAsString();
    final match = RegExp(
      r'-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----',
    ).firstMatch(pem);
    if (match == null) {
      throw const FormatException('Missing server certificate');
    }
    final der = base64.decode(match.group(1)!.replaceAll(RegExp(r'\s'), ''));
    if (der.isEmpty) {
      throw const FormatException('Empty server certificate');
    }
    return sha256.convert(der).toString();
  }

  Future<SecurityContext> securityContext() async {
    final context = SecurityContext();
    context.useCertificateChainBytes(await File(certificatePath).readAsBytes());
    context.usePrivateKeyBytes(await File(privateKeyPath).readAsBytes());
    return context;
  }
}

/// HTTPS host; health stays anonymous, device routes require separate authority.
class LanHealthHost {
  LanHealthHost({required this.lockFile, this.pairing});

  final LanPairingRegistry? pairing;
  int _activeRequests = 0;
  DateTime _windowStart = DateTime.now();
  int _pairRequests = 0;
  int _statusRequests = 0;

  final File lockFile;
  static final Set<String> _ownedPaths = {};

  static bool ownsLockFile(File file) => _ownedPaths.contains(file.absolute.path);
  RandomAccessFile? _lock;
  HttpServer? _server;
  String? _ownedPath;
  int _requestSequence = 0;
  Future<void>? _starting;
  Future<void>? _stopping;

  bool get running => _server != null;

  Future<void> start(LanHostConfig config) {
    if (_starting != null || _stopping != null) {
      throw StateError('Host already starting or running');
    }
    return _starting = _start(config);
  }

  Future<void> _start(LanHostConfig config) async {
    if (_ownedPath != null) {
      throw StateError('Host already starting or running');
    }
    final path = lockFile.absolute.path;
    if (!_ownedPaths.add(path)) {
      throw StateError('Backend already owned');
    }
    _ownedPath = path;
    try {
      await lockFile.parent.create(recursive: true);
      _lock = await lockFile.open(mode: FileMode.append);
      await _lock!.lock(FileLock.exclusive, 0, 1);
      await pairing?.load();
      final context = await config.securityContext();
      _server = await HttpServer.bindSecure(
        config.address,
        config.port,
        context,
        shared: false,
      );
      pairing?.setActive(true);
      _server!.idleTimeout = const Duration(seconds: 5);
      _server!.listen(
        (request) => unawaited(_respond(request)),
        onError: (Object _) {},
      );
    } catch (_) {
      await _close();
      rethrow;
    }
  }

  Future<void> _respond(HttpRequest request) async {
    _activeRequests++;
    try {
      final response = request.response;
      response.headers.contentType = ContentType.json;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.persistentConnection = false;
      if (request.uri.path == LanContract.healthPath &&
          request.method == 'GET' &&
          request.uri.query.isEmpty &&
          request.contentLength <= 0 &&
          request.headers.value(HttpHeaders.transferEncodingHeader) == null) {
        response.statusCode = HttpStatus.ok;
        response.write(jsonEncode(const LanHealth().toJson()));
      } else if (pairing != null && await _deviceRoute(request)) {
        // Response written by the bounded device router.
      } else {
        final code = request.uri.path == LanContract.healthPath
            ? LanErrorCode.invalidRequest
            : LanErrorCode.notFound;
        response.statusCode = code.httpStatus;
        response.write(jsonEncode(
          LanFailure(code, requestId: 'health-${++_requestSequence}').toJson(),
        ));
      }
      await response.close();
    } catch (_) {
      // Disconnects must not escape into the desktop event loop.
    } finally {
      _activeRequests--;
    }
  }


  Future<Map<String, dynamic>> _body(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      if (bytes.length + chunk.length > 4096) {
        throw const PairingFailure(LanErrorCode.invalidRequest);
      }
      bytes.addAll(chunk);
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw const PairingFailure(LanErrorCode.invalidRequest);
    }
    return json;
  }

  Future<bool> _deviceRoute(HttpRequest request) async {
    final path = request.uri.path;
    final exchange = path == '${LanContract.basePath}/pair/exchange';
    final status = path == '${LanContract.basePath}/pair/status';
    final bootstrap = path == '${LanContract.basePath}/bootstrap';
    if (!exchange && !status && !bootstrap) return false;
    try {
      if (_activeRequests > 32) throw const PairingFailure(LanErrorCode.rateLimited);
      final now = DateTime.now();
      if (now.difference(_windowStart) >= const Duration(minutes: 1)) {
        _windowStart = now;
        _pairRequests = 0;
        _statusRequests = 0;
      }
      if (exchange ? ++_pairRequests > 20 : ++_statusRequests > 240) {
        throw const PairingFailure(LanErrorCode.rateLimited);
      }
      if (request.uri.query.isNotEmpty || request.contentLength > 4096 ||
          request.method != (exchange ? 'POST' : 'GET')) {
        throw const PairingFailure(LanErrorCode.invalidRequest);
      }
      PairedPhone phone;
      if (exchange) {
        if (request.headers.contentType?.mimeType != 'application/json') {
          throw const PairingFailure(LanErrorCode.invalidRequest);
        }
        final json = await _body(request).timeout(const Duration(seconds: 5));
        if (json.length != 3 || json['code'] is! String ||
            json['name'] is! String || json['token'] is! String) {
          throw const PairingFailure(LanErrorCode.invalidRequest);
        }
        phone = await pairing!.request(json['code'] as String,
          json['name'] as String, json['token'] as String);
      } else {
        if (request.contentLength > 0 ||
            request.headers.value(HttpHeaders.transferEncodingHeader) != null) {
          throw const PairingFailure(LanErrorCode.invalidRequest);
        }
        final auth = request.headers.value(HttpHeaders.authorizationHeader);
        if (auth == null || !auth.startsWith('Bearer ')) {
          throw const PairingFailure(LanErrorCode.unauthenticated);
        }
        phone = await pairing!.status(auth.substring(7), requireApproved: bootstrap);
      }
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({
        'apiVersion': 1, 'device': phone.toJson(),
        if (bootstrap) 'permissions': <String>['connection'],
      }));
    } catch (error) {
      final code = error is PairingFailure ? error.code
          : error is FormatException || error is TimeoutException
              ? LanErrorCode.invalidRequest : LanErrorCode.internal;
      request.response.statusCode = code.httpStatus;
      request.response.write(jsonEncode(
        LanFailure(code, requestId: 'device-${++_requestSequence}').toJson(),
      ));
    }
    return true;
  }

  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    try {
      await _starting;
    } catch (_) {
      // Startup already cleaned up after its failure.
    }
    try {
      await _close();
    } finally {
      _starting = null;
      _stopping = null;
    }
  }

  Future<void> _close() async {
    pairing?.setActive(false);
    final server = _server;
    _server = null;
    try {
      if (server != null) {
        await server.close(force: true);
      }
    } finally {
      final handle = _lock;
      _lock = null;
      try {
        // Closing this exact handle releases its OS lock, including after crash.
        await handle?.close();
      } finally {
        final path = _ownedPath;
        _ownedPath = null;
        if (path != null) {
          _ownedPaths.remove(path);
        }
      }
    }
  }
}
