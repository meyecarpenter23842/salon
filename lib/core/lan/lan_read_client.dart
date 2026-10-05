import 'dart:convert';
import 'dart:io';

import 'lan_contract.dart';
import 'lan_health_client.dart';
import 'lan_pairing.dart';
import 'lan_read_models.dart';

abstract interface class SalonReadClient {
  Future<SalonReadPage> read(LanConnection connection, String token, SalonReadQuery query);
}

class PinnedSalonReadClient implements SalonReadClient {
  const PinnedSalonReadClient({this.timeout = const Duration(seconds: 8)});
  final Duration timeout;
  @override
  Future<SalonReadPage> read(LanConnection connection, String token, SalonReadQuery query) async {
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
    client.connectionTimeout = timeout;
    client.findProxy = (_) => 'DIRECT';
    client.badCertificateCallback = connection.matches;
    try {
      return await _read(client, connection, token, query).timeout(timeout);
    } finally { client.close(force: true); }
  }

  Future<SalonReadPage> _read(HttpClient client, LanConnection connection,
      String token, SalonReadQuery query) async {
    final uri = connection.apiUrl.replace(
      path: '${LanContract.basePath}/${query.kind.name}', queryParameters: query.parameters);
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close();
    final certificate = response.certificate;
    if (certificate == null ||
        !connection.matches(certificate, connection.apiUrl.host, connection.apiUrl.port)) {
      throw const FormatException('Certificate mismatch');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 262144) throw const FormatException('Response too large');
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
    return SalonReadPage.fromJson(json);
  }
}
