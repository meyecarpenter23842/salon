import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'lan_contract.dart';
import 'lan_changes.dart';
import 'lan_pairing.dart';
import 'lan_read_models.dart';
import 'lan_workflow_service.dart';
import 'lan_write_contract.dart';

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
  LanHealthHost({required this.lockFile, this.pairing, this.reader, this.workflow, this.changes});

  final LanPairingRegistry? pairing;
  final SalonReadRepository? reader;
  final LanWorkflowBackend? workflow;
  final LanChangeSource? changes;
  int _changeRequests = 0;
  int _commandRequests = 0;
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
      } else if (pairing != null && await _changeRoute(request)) {
        // Approved change watermarks carry no salon records.
      } else if (pairing != null && await _workflowRoute(request)) {
        // Device writes retain authority until their transaction finishes.
      } else if (pairing != null && await _readRoute(request)) {
        // Approved read authority is checked before and after the database read.
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


  Future<Map<String, dynamic>> _body(HttpRequest request, {int maximum = 4096}) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      if (bytes.length + chunk.length > maximum) {
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
        _commandRequests = 0; _changeRequests = 0;
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
        if (bootstrap) 'permissions': <String>['connection',
          if (phone.canReadSalon) ...['customers.read', 'invoices.read', 'appointments.read']],
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

  Future<bool> _readRoute(HttpRequest request) async {
    final kinds = SalonReadKind.values.where((kind) =>
      request.uri.path == '${LanContract.basePath}/${kind.name}');
    if (kinds.isEmpty) return false;
    // Health-only hosts retain their original routing surface.
    if (reader == null) return false;
    try {
      if (_activeRequests > 32) throw const PairingFailure(LanErrorCode.rateLimited);
      final now = DateTime.now();
      if (now.difference(_windowStart) >= const Duration(minutes: 1)) {
        _windowStart = now; _pairRequests = 0; _statusRequests = 0; _commandRequests = 0; _changeRequests = 0;
      }
      if (++_statusRequests > 240) { throw const PairingFailure(LanErrorCode.rateLimited); }
      if (request.method != 'GET' || request.contentLength > 0 ||
          request.headers.value(HttpHeaders.transferEncodingHeader) != null ||
          request.uri.query.length > 1024) {
        throw const PairingFailure(LanErrorCode.invalidRequest);
      }
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      if (auth == null || !auth.startsWith('Bearer ')) {
        throw const PairingFailure(LanErrorCode.unauthenticated);
      }
      final token = auth.substring(7);
      await pairing!.status(token, requireRead: true);
      final query = SalonReadQuery.fromUri(kinds.single, request.uri);
      final page = await reader!.read(query).timeout(const Duration(seconds: 5));
      final payload = jsonEncode(page.toJson());
      if (utf8.encode(payload).length > 262144) {
        throw const PairingFailure(LanErrorCode.unavailable);
      }
      await pairing!.status(token, requireRead: true);
      request.response.statusCode = HttpStatus.ok;
      request.response.write(payload);
    } catch (error) {
      final code = error is PairingFailure ? error.code
          : error is FormatException ? LanErrorCode.invalidRequest
          : error is TimeoutException ? LanErrorCode.unavailable : LanErrorCode.internal;
      request.response.statusCode = code.httpStatus;
      request.response.write(jsonEncode(
        LanFailure(code, requestId: 'read-${++_requestSequence}').toJson()));
    }
    return true;
  }


  Future<bool> _workflowRoute(HttpRequest request) async {
    final suffix = request.uri.path;
    final commands = suffix == '${LanContract.basePath}/commands';
    final editor = suffix == '${LanContract.basePath}/editor';
    final catalog = suffix == '${LanContract.basePath}/catalog';
    if (workflow == null || (!commands && !editor && !catalog)) return false;
    try {
      if (_activeRequests > 32) throw const PairingFailure(LanErrorCode.rateLimited);
      final now = DateTime.now();
      if (now.difference(_windowStart) >= const Duration(minutes: 1)) {
        _windowStart = now; _pairRequests = 0; _statusRequests = 0; _commandRequests = 0; _changeRequests = 0;
      }
      final writing = commands && request.method == 'POST';
      if (writing ? ++_commandRequests > 60 : ++_statusRequests > 240) { throw const PairingFailure(LanErrorCode.rateLimited); }
      if (request.uri.query.length > 1024 || request.contentLength > 16384 ||
          request.uri.queryParametersAll.values.any((v) => v.length != 1) ||
          request.method != (writing ? 'POST' : 'GET')) { throw const PairingFailure(LanErrorCode.invalidRequest); }
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      if (auth == null || !auth.startsWith('Bearer ')) throw const PairingFailure(LanErrorCode.unauthenticated);
      final token = auth.substring(7);
      final phone = await pairing!.status(token, requireRead: true);
      Object payload;
      if (writing) {
        if (request.uri.query.isNotEmpty || request.headers.contentType?.mimeType != 'application/json') {
          throw const PairingFailure(LanErrorCode.invalidRequest);
        }
        final json = await _body(request, maximum: 16384).timeout(const Duration(seconds: 5));
        final command = LanWriteCommand.fromJson(json);
        final result = await pairing!.withWriteAuthority(token, command.operation,
          (authorized) => workflow!.execute(authorized, command));
        payload = {'apiVersion': 1, 'result': result.toJson()};
      } else {
        if (request.contentLength > 0 || request.headers.value(HttpHeaders.transferEncodingHeader) != null) {
          throw const PairingFailure(LanErrorCode.invalidRequest);
        }
        final q = request.uri.queryParameters;
        if (commands) {
          if (q.length != 1 || q['commandId'] == null) throw const FormatException('Command id required');
          LanContract.validateIdentity(q['commandId']!, 'commandId');
          final result = await workflow!.result(phone.id, q['commandId']!);
          payload = {'apiVersion': 1, 'result': result?.toJson()};
        } else if (editor) {
          if (q.keys.any((k) => !['kind', 'id'].contains(k)) || q['kind'] == null) throw const FormatException('Editor query');
          payload = (await workflow!.editor(q['kind']!, q['id'])).toJson();
        } else {
          if (q.keys.any((k) => !['kind', 'q', 'offset'].contains(k)) || q['kind'] == null) throw const FormatException('Catalog query');
          final offset = q['offset'] == null ? 0 : int.tryParse(q['offset']!);
          if (offset == null) throw const FormatException('Offset');
          payload = (await workflow!.catalog(q['kind']!, q['q'] ?? '', offset)).toJson();
        }
        await pairing!.status(token, requireRead: true);
      }
      final encoded = jsonEncode(payload);
      if (utf8.encode(encoded).length > 262144) throw const PairingFailure(LanErrorCode.unavailable);
      request.response.statusCode = HttpStatus.ok;
      request.response.write(encoded);
    } catch (error) {
      final code = error is PairingFailure ? error.code :
        error is FormatException || error is ArgumentError || error is TimeoutException ?
          LanErrorCode.invalidRequest : LanErrorCode.internal;
      request.response.statusCode = code.httpStatus;
      request.response.write(jsonEncode(LanFailure(code, requestId: 'write-${++_requestSequence}').toJson()));
    }
    return true;
  }

  Future<bool> _changeRoute(HttpRequest request) async {
    if (changes == null || request.uri.path != '${LanContract.basePath}/changes') return false;
    try {
      if (_activeRequests > 32) throw const PairingFailure(LanErrorCode.rateLimited);
      final now = DateTime.now();
      if (now.difference(_windowStart) >= const Duration(minutes: 1)) {
        _windowStart = now; _pairRequests = 0; _statusRequests = 0; _commandRequests = 0; _changeRequests = 0;
      }
      if (++_changeRequests > 600) throw const PairingFailure(LanErrorCode.rateLimited);
      if (request.method != 'GET' || request.contentLength > 0 ||
          request.headers.value(HttpHeaders.transferEncodingHeader) != null ||
          request.uri.query.length > 200 || request.uri.queryParametersAll.values.any((v) => v.length != 1)) {
        throw const PairingFailure(LanErrorCode.invalidRequest);
      }
      final q = request.uri.queryParameters;
      final cursor = int.tryParse(q['cursor'] ?? '');
      if (q.keys.any((k) => !['epoch', 'cursor'].contains(k)) || cursor == null ||
          cursor < 0 || cursor > 9007199254740991 ||
          q['epoch'] != null && !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(q['epoch']!)) {
        throw const PairingFailure(LanErrorCode.invalidRequest);
      }
      final auth = request.headers.value(HttpHeaders.authorizationHeader);
      if (auth == null || !auth.startsWith('Bearer ')) throw const PairingFailure(LanErrorCode.unauthenticated);
      final token = auth.substring(7);
      await pairing!.status(token, requireRead: true);
      final value = await changes!.read(q['epoch'], cursor).timeout(const Duration(seconds: 5));
      await pairing!.status(token, requireRead: true);
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode(value.toJson()));
    } catch (error) {
      final code = error is PairingFailure ? error.code :
        error is FormatException ? LanErrorCode.invalidRequest :
        error is TimeoutException ? LanErrorCode.unavailable : LanErrorCode.internal;
      request.response.statusCode = code.httpStatus;
      request.response.write(jsonEncode(LanFailure(code, requestId: 'changes-${++_requestSequence}').toJson()));
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
      // Drain accepted device writes before releasing ownership to another process.
      await pairing?.settled;
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

