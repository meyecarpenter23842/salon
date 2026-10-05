import 'dart:convert';
import 'dart:io';
import 'lan_contract.dart';
import 'lan_health_client.dart';
import 'lan_pairing.dart';
import 'lan_write_contract.dart';
import 'lan_workflow_models.dart';

abstract interface class LanWorkflowClient {
  Future<LanEditorSnapshot> editor(LanConnection connection, String token, String kind, String? id);
  Future<LanCatalogPage> catalog(LanConnection connection, String token, String kind, String query, int offset);
  Future<LanWriteResult> send(LanConnection connection, String token, LanWriteCommand command);
  Future<LanWriteResult?> result(LanConnection connection, String token, String commandId);
}

class PinnedLanWorkflowClient implements LanWorkflowClient {
  const PinnedLanWorkflowClient({this.timeout = const Duration(seconds: 8)});
  final Duration timeout;
  @override
  Future<LanEditorSnapshot> editor(LanConnection c, String token, String kind, String? id) async =>
    LanEditorSnapshot.fromJson(await _request(c, token, 'editor', {'kind': kind, 'id': ?id}));
  @override
  Future<LanCatalogPage> catalog(LanConnection c, String token, String kind, String query, int offset) async =>
    LanCatalogPage.fromJson(await _request(c, token, 'catalog', {'kind': kind, 'q': query, 'offset': '$offset'}));
  @override
  Future<LanWriteResult> send(LanConnection c, String token, LanWriteCommand command) async =>
    LanWriteResult.fromJson(Map<String, dynamic>.from(
      (await _request(c, token, 'commands', {}, command.toJson()))['result'] as Map));
  @override
  Future<LanWriteResult?> result(LanConnection c, String token, String commandId) async {
    final value = (await _request(c, token, 'commands', {'commandId': commandId}))['result'];
    return value == null ? null : LanWriteResult.fromJson(Map<String, dynamic>.from(value as Map));
  }
  Future<Map<String, dynamic>> _request(LanConnection c, String token, String path,
      Map<String, String> query, [Map<String, Object?>? body]) async {
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
    client.connectionTimeout = timeout;
    client.findProxy = (_) => 'DIRECT';
    client.badCertificateCallback = c.matches;
    try {
      return await (() async {
        final uri = c.apiUrl.replace(path: '${LanContract.basePath}/$path',
          queryParameters: query.isEmpty ? null : query);
        final request = await client.openUrl(body == null ? 'GET' : 'POST', uri);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.add(utf8.encode(jsonEncode(body)));
        }
        final response = await request.close();
        final certificate = response.certificate;
        if (certificate == null || !c.matches(certificate, c.apiUrl.host, c.apiUrl.port)) {
          throw const FormatException('Certificate mismatch');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 262144) throw const FormatException('Response too large');
          bytes.addAll(chunk);
        }
        final json = jsonDecode(utf8.decode(bytes));
        if (json is! Map<String, dynamic> || json['apiVersion'] != 1) throw const FormatException('Unsupported response');
        if (response.statusCode != HttpStatus.ok) {
          final error = json['error'];
          final name = error is Map ? error['code'] : null;
          final codes = LanErrorCode.values.where((c) => c.wireName == name);
          throw PairingFailure(codes.isEmpty ? LanErrorCode.unavailable : codes.first);
        }
        return json;
      })().timeout(timeout);
    } finally { client.close(force: true); }
  }
}
