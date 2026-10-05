import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';

void main() {
  test('only HTTPS API root and explicit SHA-256 pin accepted', () {
    for (final url in [
      'http://salon/api/staff/v1', 'https://user:secret@salon/api/staff/v1',
      'https://salon/api/staff/v1?token=x', 'https://salon/api/staff/v1#x',
      'https://salon/customers',
    ]) {
      expect(() => LanConnection(url, 'a' * 64), throwsFormatException);
    }
    expect(() => LanConnection('https://salon/api/staff/v1', ''),
      throwsFormatException);
    final normalized = LanConnection('https://salon/api/staff/v1/',
      List.filled(32, 'AA').join(':'));
    expect(normalized.certificateSha256, 'a' * 64);
    expect(normalized.healthUrl.toString(), 'https://salon/api/staff/v1/health');
  });

  final fixture = Platform.environment['SALON_TEST_TLS_DIR'];
  if (fixture == null) {
    test('pin integration requires CI TLS fixture', () {},
      skip: 'Set SALON_TEST_TLS_DIR to generated PEM fixtures.');
    return;
  }
  HttpServer? server;
  late String fingerprint;
  Future<void> start(void Function(HttpRequest) respond) async {
    final pem = await File('$fixture/certificate.pem').readAsString();
    final base64 = pem.replaceAll(
      RegExp(r'-----BEGIN CERTIFICATE-----|-----END CERTIFICATE-----|\s'), '');
    fingerprint = sha256.convert(base64Decode(base64)).toString();
    final context = SecurityContext()
      ..useCertificateChain('$fixture/certificate.pem')
      ..usePrivateKey('$fixture/private-key.pem');
    server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    server!.listen(respond);
  }
  LanConnection connection([String? pin]) => LanConnection(
    'https://127.0.0.1:${server!.port}/api/staff/v1', pin ?? fingerprint);
  tearDown(() async {
    await server?.close(force: true);
    server = null;
  });

  test('real self-signed TLS works only with exact entered certificate pin',
    () async {
      await start((request) {
        expect(request.uri.path, '/api/staff/v1/health');
        request.response.write('{"apiVersion":1,"status":"ok"}');
        unawaited(request.response.close());
      });
      await const PinnedLanHealthClient().check(connection());
      await expectLater(
        const PinnedLanHealthClient().check(connection('0' * 64)),
        throwsA(isA<HandshakeException>()));
    });

  test('redirects never change trusted endpoint', () async {
    await start((request) {
      request.response.statusCode = 302;
      request.response.headers.set('location', 'https://example.invalid');
      unawaited(request.response.close());
    });
    await expectLater(const PinnedLanHealthClient().check(connection()),
      throwsFormatException);
  });

  test('wrong version and oversized health replies rejected', () async {
    var oversized = false;
    await start((request) {
      request.response.write(oversized ? 'x' * 4097 :
        '{"apiVersion":2,"status":"ok"}');
      unawaited(request.response.close());
    });
    await expectLater(const PinnedLanHealthClient().check(connection()),
      throwsFormatException);
    oversized = true;
    await expectLater(const PinnedLanHealthClient().check(connection()),
      throwsFormatException);
  });

  test('full operation has bounded timeout', () async {
    await start((_) {});
    await expectLater(
      const PinnedLanHealthClient(timeout: Duration(milliseconds: 100))
        .check(connection()),
      throwsA(isA<TimeoutException>()));
  });
}
