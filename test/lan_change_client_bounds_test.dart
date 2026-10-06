import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_changes.dart';
import 'package:salonmanager/core/lan/lan_health_host.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
void main() {
  final fixture = Platform.environment['SALON_TEST_TLS_DIR'];
  if (fixture == null) return;
  test('pinned change client bounds response, version, redirects and wait time', () async {
    final config = LanHostConfig(address: InternetAddress.loopbackIPv4, port: 8743,
      certificatePath: '$fixture/certificate.pem', privateKeyPath: '$fixture/private-key.pem');
    final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, await config.securityContext());
    final connection = LanConnection('https://127.0.0.1:${server.port}/api/staff/v1', await config.certificateSha256());
    String mode = 'oversized'; int requests = 0;
    server.listen((request) async {
      requests++;
      try {
        request.response.headers.contentType = ContentType.json;
        if (mode == 'oversized') {
          request.response.write(jsonEncode({'apiVersion': 1, 'epoch': 'x' * 5000}));
        } else if (mode == 'version') {
          request.response.write(jsonEncode({'apiVersion': 2}));
        } else if (mode == 'redirect') {
          request.response.statusCode = 302; request.response.headers.set(HttpHeaders.locationHeader, '/api/staff/v1/health');
          request.response.write('{}');
        } else { await Future<void>.delayed(const Duration(seconds: 1)); request.response.write('{}'); }
        await request.response.close();
      } catch (_) { /* Client timeout/close is expected. */ }
    });
    try {
      const client = PinnedLanChangeClient();
      for (final value in ['oversized', 'version', 'redirect']) {
        mode = value; final previous = requests;
        await expectLater(client.read(connection, 'c' * 64, null, 0), throwsFormatException);
        expect(requests, previous + 1);
      }
      mode = 'timeout';
      await expectLater(const PinnedLanChangeClient(timeout: Duration(milliseconds: 100)).read(connection, 'c' * 64, null, 0),
        throwsA(isA<TimeoutException>()));
    } finally { await server.close(force: true); }
  });
}
