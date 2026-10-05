import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_health_host.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_workflow_client.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'support/mobile_workflow_fixture.dart';

void main() {
  final fixture = Platform.environment['SALON_TEST_TLS_DIR'];
  if (fixture == null) { test('CI supplies TLS fixture', () {}, skip: 'Requires SALON_TEST_TLS_DIR'); return; }
  late Directory root;
  late LanPairingRegistry registry;
  late LanHealthHost host;
  late LanHostConfig config;
  late LanConnection connection;
  late MobileWorkflowFixture f;
  const client = PinnedLanWorkflowClient();
  setUp(() async {
    await SalonDatabase.instance.close();
    f = await mobileFixture();
    root = await Directory.systemTemp.createTemp('salon-workflow-https-');
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port; await probe.close();
    config = LanHostConfig(address: InternetAddress.loopbackIPv4, port: port,
      certificatePath: '$fixture/certificate.pem', privateKeyPath: '$fixture/private-key.pem');
    registry = LanPairingRegistry(file: File('${root.path}/devices.json'));
    host = LanHealthHost(lockFile: File('${root.path}/backend.lock'), pairing: registry, workflow: f.service);
    await host.start(config);
    connection = LanConnection(config.apiUrl.toString(), await config.certificateSha256());
  });
  tearDown(() async {
    await host.stop(); registry.dispose(); await SalonDatabase.instance.close(); await root.delete(recursive: true);
  });
  Future<PairedPhone> grant(String token, PhoneWriteRole role) async {
    final phone = await registry.request(await registry.createCode(), 'Phone', token);
    await registry.decide(phone.id, PhoneAccess.approved);
    await registry.setReadAccess(phone.id, true);
    await registry.setWriteRole(phone.id, role);
    return registry.status(token);
  }
  test('HTTPS actual SQLite workflow enforces separate role, actor-scoped retry/result and revocation', () async {
    final token = newDeviceSecret();
    final command = await f.command(LanWriteOperation.customerCreate, customerPayload());
    await expectLater(client.send(connection, token, command), throwsA(isA<PairingFailure>()));
    final phone = await grant(token, PhoneWriteRole.none);
    await expectLater(client.send(connection, token, command), throwsA(isA<PairingFailure>()));
    expect(await f.db.query('lan_commands'), isEmpty);
    await registry.setWriteRole(phone.id, PhoneWriteRole.staff);
    final created = await client.send(connection, token, command);
    expect((await client.send(connection, token, command)).id, created.id);
    expect((await client.result(connection, token, command.commandId))!.id, created.id);
    final other = newDeviceSecret(); await grant(other, PhoneWriteRole.cashier);
    expect(await client.result(connection, other, command.commandId), isNull);
    expect((await client.editor(connection, token, 'customer', created.id)).values['fullName'], 'Khách Android');
    expect((await client.catalog(connection, token, 'services', '', 0)).items, hasLength(2));
    await registry.decide(phone.id, PhoneAccess.revoked);
    await expectLater(client.send(connection, token, command), throwsA(isA<PairingFailure>()));
    await expectLater(client.editor(connection, token, 'customer', created.id), throwsA(isA<PairingFailure>()));
    expect(await f.db.query('customers'), hasLength(2));
  });
  test('wrong certificate and malformed envelopes fail without mutation or private error text', () async {
    final token = newDeviceSecret(); await grant(token, PhoneWriteRole.owner);
    final command = await f.command(LanWriteOperation.customerCreate, customerPayload());
    await expectLater(client.send(LanConnection(config.apiUrl.toString(), '0' * 64), token, command),
      throwsA(isA<HandshakeException>()));
    final trust = SecurityContext(withTrustedRoots: false);
    trust.setTrustedCertificatesBytes(await File(config.certificatePath).readAsBytes());
    for (final body in [
        {...command.toJson(), 'role': 'owner'},
        {...command.toJson(), 'operation': 'sqlExecute'},
        {...command.toJson(), 'payload': {'fullName': 'a' * 17000}},
    ]) {
      final raw = HttpClient(context: trust);
      final encoded = utf8.encode(jsonEncode(body));
      try {
        final request = await raw.postUrl(Uri.parse('${config.apiUrl}/commands'));
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        request.persistentConnection = false;
        request.headers.contentType = ContentType.json;
        request.add(encoded);
        final response = await request.close();
        expect(response.statusCode, 400);
        expect(response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
        final text = await utf8.decoder.bind(response).join();
        expect(text, isNot(contains('Khách gốc'))); expect(text, isNot(contains(token)));
        expect(text, isNot(contains(root.path))); expect(text, isNot(contains('SELECT')));
      } on HttpException {
        // Oversized chunked bodies may be aborted as soon as the bound is exceeded.
        expect(encoded.length, greaterThan(16384));
      } finally { raw.close(force: true); }
    }
    expect(await f.db.query('customers'), hasLength(1)); expect(await f.db.query('lan_commands'), isEmpty);
  });
}
