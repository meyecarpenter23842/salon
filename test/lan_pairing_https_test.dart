import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_health_host.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_pairing_client.dart';

void main() {
  final fixture = Platform.environment['SALON_TEST_TLS_DIR'];
  if (fixture == null) {
    test('CI supplies TLS fixture', () {}, skip: 'Requires SALON_TEST_TLS_DIR');
    return;
  }
  late Directory root;
  late LanHealthHost host;
  late LanPairingRegistry registry;
  late LanHostConfig config;
  late LanConnection connection;
  const client = PinnedLanPairingClient();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('salon-pair-https-');
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    config = LanHostConfig(address: InternetAddress.loopbackIPv4, port: port,
      certificatePath: '$fixture/certificate.pem', privateKeyPath: '$fixture/private-key.pem');
    registry = LanPairingRegistry(file: File('${root.path}/devices.json'));
    host = LanHealthHost(lockFile: File('${root.path}/backend.lock'), pairing: registry);
    await host.start(config);
    connection = LanConnection(config.apiUrl.toString(), await config.certificateSha256());
  });
  tearDown(() async {
    await host.stop();
    registry.dispose();
    await root.delete(recursive: true);
  });

  test('real pinned client request, desktop approve, restart, revoke, re-pair', () async {
    final token = newDeviceSecret();
    final code = await registry.createCode();
    final phone = await client.request(connection, code, 'Android A', token);
    expect(phone.state, PhoneAccess.pending);
    await expectLater(client.bootstrap(connection, token), throwsA(isA<PairingFailure>()));
    expect((await client.request(connection, code, 'Android A', token)).id, phone.id);
    await registry.decide(phone.id, PhoneAccess.approved);
    expect((await client.bootstrap(connection, token)).state, PhoneAccess.approved);
    await host.stop();
    await host.start(config);
    expect((await client.bootstrap(connection, token)).state, PhoneAccess.approved);
    await registry.decide(phone.id, PhoneAccess.revoked);
    expect((await client.status(connection, token)).state, PhoneAccess.revoked);
    await expectLater(client.bootstrap(connection, token), throwsA(isA<PairingFailure>()));
    await expectLater(client.bootstrap(connection, newDeviceSecret()), throwsA(isA<PairingFailure>()));
    final other = await client.request(connection, await registry.createCode(), 'Android A', newDeviceSecret());
    expect(other.id, isNot(phone.id));
    expect(other.state, PhoneAccess.pending);
    await const PinnedLanHealthClient().check(connection);
  });

  test('wrong certificate pin refuses pairing and transmits no token to an untrusted host', () async {
    final wrong = LanConnection(connection.apiUrl.toString(), '0' * 64);
    await expectLater(client.request(wrong, await registry.createCode(), 'A', newDeviceSecret()),
      throwsA(isA<HandshakeException>()));
    expect(registry.phones, isEmpty);
  });

  test('bounded router rejects malformed bodies, query secrets, roles and HTTP admin endpoints', () async {
    final trust = SecurityContext(withTrustedRoots: false);
    trust.setTrustedCertificatesBytes(await File(config.certificatePath).readAsBytes());
    final raw = HttpClient(context: trust);
    try {
      Future<int> send(String method, String path, [String? body]) async {
        final req = await raw.openUrl(method, Uri.parse('${config.apiUrl}$path'));
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(body);
        }
        final response = await req.close();
        final status = response.statusCode;
        final text = await utf8.decoder.bind(response).join();
        expect(text, isNot(contains(root.path)));
        return status;
      }
      expect(await send('GET', '/bootstrap'), 401);
      expect(await send('GET', '/pair/status?token=secret'), 400);
      expect(await send('POST', '/pair/exchange', 'x' * 4097), 400);
      expect(await send('POST', '/pair/exchange', jsonEncode({
        'code': await registry.createCode(), 'name': 'A', 'token': newDeviceSecret(), 'role': 'owner',
      })), 400);
      expect(await send('POST', '/pair/approve', '{}'), 404);
      expect(await send('GET', '/customers'), 404);
      for (var i = 0; i < 20; i++) {
        await send('POST', '/pair/exchange', '{}');
      }
      expect(await send('POST', '/pair/exchange', '{}'), 429);
      expect(registry.phones, isEmpty);
    } finally { raw.close(force: true); }
  });
}
