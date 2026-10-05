import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_health_host.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_read_client.dart';
import 'package:salonmanager/core/lan/lan_read_models.dart';

class _Reader implements SalonReadRepository {
  int reads = 0;
  Completer<void>? delay;
  @override
  Future<SalonReadPage> read(SalonReadQuery query) async {
    reads++;
    await delay?.future;
    return const SalonReadPage(salonDate: '2026-10-05', records: [
      SalonReadRecord(id: 'customer-1', title: 'Private customer', subtitle: '0901234567'),
    ]);
  }
}

void main() {
  final fixture = Platform.environment['SALON_TEST_TLS_DIR'];
  if (fixture == null) {
    test('CI supplies TLS fixture', () {}, skip: 'Requires SALON_TEST_TLS_DIR');
    return;
  }
  late Directory root;
  late LanPairingRegistry registry;
  late LanHealthHost host;
  late LanHostConfig config;
  late LanConnection connection;
  late _Reader reader;
  const client = PinnedSalonReadClient();
  final query = SalonReadQuery(SalonReadKind.customers);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('salon-read-https-');
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    config = LanHostConfig(address: InternetAddress.loopbackIPv4, port: port,
      certificatePath: '$fixture/certificate.pem', privateKeyPath: '$fixture/private-key.pem');
    registry = LanPairingRegistry(file: File('${root.path}/devices.json'));
    reader = _Reader();
    host = LanHealthHost(lockFile: File('${root.path}/backend.lock'), pairing: registry, reader: reader);
    await host.start(config);
    connection = LanConnection(config.apiUrl.toString(), await config.certificateSha256());
  });
  tearDown(() async {
    await host.stop(); registry.dispose(); await root.delete(recursive: true);
  });

  test('unknown, pending, approved connection-only and revoked tokens never read SQLite', () async {
    final token = newDeviceSecret();
    await expectLater(client.read(connection, token, query), throwsA(isA<PairingFailure>()));
    final phone = await registry.request(await registry.createCode(), 'Phone', token);
    await expectLater(client.read(connection, token, query), throwsA(isA<PairingFailure>()));
    await registry.decide(phone.id, PhoneAccess.approved);
    await expectLater(client.read(connection, token, query), throwsA(isA<PairingFailure>()));
    expect(reader.reads, 0);
    await registry.setReadAccess(phone.id, true);
    expect((await client.read(connection, token, query)).records.single.title, 'Private customer');
    await registry.setReadAccess(phone.id, false);
    await expectLater(client.read(connection, token, query), throwsA(isA<PairingFailure>()));
    await registry.setReadAccess(phone.id, true);
    await host.stop(); await host.start(config);
    expect((await registry.status(token)).canReadSalon, isTrue);
    await registry.decide(phone.id, PhoneAccess.revoked);
    expect((await registry.status(token)).canReadSalon, isFalse);
    await expectLater(client.read(connection, token, query), throwsA(isA<PairingFailure>()));
    expect(reader.reads, 1);
    await const PinnedLanHealthClient().check(connection);
    expect(reader.reads, 1);
  });

  test('permission revocation during an in-flight read suppresses all private data', () async {
    final token = newDeviceSecret();
    final phone = await registry.request(await registry.createCode(), 'Phone', token);
    await registry.decide(phone.id, PhoneAccess.approved);
    await registry.setReadAccess(phone.id, true);
    reader.delay = Completer<void>();
    final result = client.read(connection, token, query);
    final assertion = expectLater(result, throwsA(isA<PairingFailure>()));
    while (reader.reads == 0) { await Future<void>.delayed(const Duration(milliseconds: 10)); }
    await registry.setReadAccess(phone.id, false);
    reader.delay!.complete();
    await assertion;
  });

  test('wrong pin, write verbs and malformed queries do not read data or expose internals', () async {
    final token = newDeviceSecret();
    final phone = await registry.request(await registry.createCode(), 'Phone', token);
    await registry.decide(phone.id, PhoneAccess.approved);
    await registry.setReadAccess(phone.id, true);
    await expectLater(client.read(LanConnection(config.apiUrl.toString(), '0' * 64), token, query),
      throwsA(isA<HandshakeException>()));
    final trust = SecurityContext(withTrustedRoots: false);
    trust.setTrustedCertificatesBytes(await File(config.certificatePath).readAsBytes());
    final raw = HttpClient(context: trust);
    try {
      for (final (method, suffix) in [
        ('POST', '/customers'), ('PATCH', '/invoices'), ('DELETE', '/appointments'),
        ('GET', '/customers?limit=26'), ('GET', '/customers?q=x&q=y'),
        ('GET', '/customers?token=secret'), ('GET', '/appointments?day=2026-02-30'),
      ]) {
        final request = await raw.openUrl(method, Uri.parse('${config.apiUrl}$suffix'));
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        final response = await request.close();
        expect(response.statusCode, 400);
        expect(response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
        final text = await utf8.decoder.bind(response).join();
        expect(text, isNot(contains('Private customer')));
        expect(text, isNot(contains(token)));
        expect(text, isNot(contains(root.path)));
      }
    } finally { raw.close(force: true); }
    expect(reader.reads, 0);
  });

  test('legacy approved stores require a separate owner read grant after upgrade', () async {
    final token = newDeviceSecret();
    final phone = await registry.request(await registry.createCode(), 'Old phone', token);
    await registry.decide(phone.id, PhoneAccess.approved);
    final json = jsonDecode(await registry.file.readAsString()) as Map<String, dynamic>;
    for (final row in json['phones'] as List) { (row as Map).remove('canReadSalon'); }
    await host.stop();
    await registry.file.writeAsString(jsonEncode(json));
    await host.start(config);
    expect((await registry.status(token)).state, PhoneAccess.approved);
    expect((await registry.status(token)).canReadSalon, isFalse);
    await expectLater(client.read(connection, token, query), throwsA(isA<PairingFailure>()));
    expect(reader.reads, 0);
  });
}
