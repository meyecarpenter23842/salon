import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lan_contract.dart';

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

  Future<SecurityContext> securityContext() async {
    final context = SecurityContext();
    context.useCertificateChainBytes(await File(certificatePath).readAsBytes());
    context.usePrivateKeyBytes(await File(privateKeyPath).readAsBytes());
    return context;
  }
}

/// HTTPS liveness host. No repository, database, auth or mutation dependency.
class LanHealthHost {
  LanHealthHost({required this.lockFile});

  final File lockFile;
  static final Set<String> _ownedPaths = {};
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
      final context = await config.securityContext();
      _server = await HttpServer.bindSecure(
        config.address,
        config.port,
        context,
        shared: false,
      );
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
      } else {
        final code = request.uri.path == LanContract.healthPath
            ? LanErrorCode.invalidRequest
            : LanErrorCode.notFound;
        response.statusCode = code.httpStatus;
        response.write(jsonEncode(
          LanFailure(code, requestId: 'health-${++_requestSequence}').toJson(),
        ));
      }
      // Do not read or parse bodies: no command endpoint exists in this host.
      await response.close();
    } catch (_) {
      // Disconnects must not escape into the desktop event loop.
    }
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
