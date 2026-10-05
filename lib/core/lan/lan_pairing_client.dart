import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lan_contract.dart';
import 'lan_health_client.dart';
import 'lan_pairing.dart';

abstract interface class LanPairingClient {
  Future<PairedPhone> request(LanConnection connection, String code, String name, String token);
  Future<PairedPhone> status(LanConnection connection, String token);
  Future<PairedPhone> bootstrap(LanConnection connection, String token);
}

class PinnedLanPairingClient implements LanPairingClient {
  const PinnedLanPairingClient({this.timeout = const Duration(seconds: 8)});
  final Duration timeout;

  @override
  Future<PairedPhone> request(LanConnection connection, String code, String name, String token) =>
      _send(connection, '/pair/exchange', token, {'code': code, 'name': name, 'token': token});
  @override
  Future<PairedPhone> status(LanConnection connection, String token) =>
      _send(connection, '/pair/status', token);
  @override
  Future<PairedPhone> bootstrap(LanConnection connection, String token) =>
      _send(connection, '/bootstrap', token);

  Future<PairedPhone> _send(LanConnection connection, String suffix, String token,
      [Map<String, String>? body]) async {
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
    client.connectionTimeout = timeout;
    client.findProxy = (_) => 'DIRECT';
    client.badCertificateCallback = connection.matches;
    try {
      return await _exchange(client, connection, suffix, token, body).timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<PairedPhone> _exchange(HttpClient client, LanConnection connection,
      String suffix, String token, Map<String, String>? body) async {
    final request = await client.openUrl(body == null ? 'GET' : 'POST',
      connection.apiUrl.replace(path: '${LanContract.basePath}$suffix'));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final certificate = response.certificate;
    if (certificate == null ||
        !connection.matches(certificate, connection.apiUrl.host, connection.apiUrl.port)) {
      throw const FormatException('Certificate mismatch');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 4096) throw const FormatException('Response too large');
      bytes.addAll(chunk);
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic> || json['apiVersion'] != 1) {
      throw const FormatException('Unsupported response');
    }
    if (response.statusCode != HttpStatus.ok) {
      final error = json['error'];
      final name = error is Map ? error['code'] : null;
      final code = LanErrorCode.values.where((c) => c.wireName == name);
      throw PairingFailure(code.isEmpty ? LanErrorCode.unavailable : code.first);
    }
    final phone = PairedPhone.fromJson(Map<String, dynamic>.from(json['device'] as Map));
    if (suffix == '/bootstrap' && phone.state != PhoneAccess.approved) {
      throw const PairingFailure(LanErrorCode.forbidden);
    }
    return phone;
  }
}
