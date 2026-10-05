import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'lan_contract.dart';

class LanConnection {
  LanConnection(String url, String fingerprint)
      : apiUrl = Uri.parse(url.trim()),
        certificateSha256 = fingerprint.replaceAll(RegExp(r'[:\s]'), '').toLowerCase() {
    if (apiUrl.scheme != 'https' ||
        apiUrl.host.isEmpty ||
        apiUrl.userInfo.isNotEmpty ||
        apiUrl.hasQuery ||
        apiUrl.hasFragment ||
        (apiUrl.path != LanContract.basePath &&
            apiUrl.path != '${LanContract.basePath}/') ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(certificateSha256)) {
      throw const FormatException('Invalid API URL or certificate fingerprint');
    }
  }

  final Uri apiUrl;
  final String certificateSha256;

  Uri get healthUrl => apiUrl.replace(path: LanContract.healthPath);

  bool matches(X509Certificate certificate, String host, int port) {
    final now = DateTime.now();
    return host == apiUrl.host &&
        port == apiUrl.port &&
        now.isAfter(certificate.startValidity) &&
        now.isBefore(certificate.endValidity) &&
        sha256.convert(certificate.der).toString() == certificateSha256;
  }
}

abstract interface class LanHealthChecker {
  Future<void> check(LanConnection connection);
}

class PinnedLanHealthClient implements LanHealthChecker {
  const PinnedLanHealthClient({this.timeout = const Duration(seconds: 8)});
  final Duration timeout;

  @override
  Future<void> check(LanConnection connection) async {
    // Trust only the entered certificate at this endpoint, even if another
    // certificate happens to be signed by a system CA.
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
    client.connectionTimeout = timeout;
    client.findProxy = (_) => 'DIRECT';
    client.badCertificateCallback = connection.matches;
    try {
      await _check(client, connection).timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _check(HttpClient client, LanConnection connection) async {
    final request = await client.getUrl(connection.healthUrl);
    request.followRedirects = false;
    final response = await request.close();
    final certificate = response.certificate;
    if (certificate == null ||
        !connection.matches(certificate, connection.apiUrl.host, connection.apiUrl.port) ||
        response.statusCode != HttpStatus.ok) {
      throw const FormatException('Health endpoint refused');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 4096) {
        throw const FormatException('Health response too large');
      }
      bytes.addAll(chunk);
    }
    final payload = jsonDecode(utf8.decode(bytes));
    if (payload is! Map ||
        payload['apiVersion'] != LanContract.apiVersion ||
        payload['status'] != 'ok') {
      throw const FormatException('Unsupported health response');
    }
  }
}
