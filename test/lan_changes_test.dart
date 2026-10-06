import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/lan/lan_changes.dart';
import 'package:salonmanager/core/lan/lan_health_host.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'support/mobile_workflow_fixture.dart';

class _DelayedChanges implements LanChangeSource {
  final entered = Completer<void>(), finish = Completer<void>();
  int reads = 0;
  @override Future<LanChangeSnapshot> read(String? epoch, int cursor) async {
    reads++; if (!entered.isCompleted) entered.complete(); await finish.future;
    return const LanChangeSnapshot('epoch-a', 1, reset: true, changed: true);
  }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // These are real generated-fixture TLS tests, not the widget HTTP mock.
  HttpOverrides.global = null;
  test('watermarks observe main/mobile writes and external Staff commits without schema changes', () async {
    await SalonDatabase.instance.close();
    final f = await mobileFixture(), source = SqliteLanChanges(SalonDatabase.instance);
    try {
      final schema = (await f.db.rawQuery('PRAGMA user_version')).single.values.single;
      final initial = await source.read(null, 0);
      expect(initial.reset, isTrue);
      expect((await source.read(initial.epoch, initial.cursor)).changed, isFalse);
      await f.db.update('inventory_stock', {'stock_on_hand': -7}, where: 'product_id = ?', whereArgs: ['product-1']);
      final local = await source.read(initial.epoch, initial.cursor); expect(local.cursor, greaterThan(initial.cursor));
      // A second SQLite connection stands in for the independently launched Staff process.
      final staff = await openDatabase(f.db.path, singleInstance: false);
      try { await staff.update('customers', {'full_name': 'Staff changed'}, where: 'id = ?', whereArgs: ['customer-1']); }
      finally { await staff.close(); }
      final external = await source.read(local.epoch, local.cursor); expect(external.cursor, greaterThan(local.cursor));
      expect((await source.read(initial.epoch, initial.cursor)).changed, isTrue); // lost notification
      expect((await source.read(external.epoch, external.cursor + 99)).reset, isTrue); // future cursor
      final parallel = await Future.wait(List.generate(10, (_) => source.read(external.epoch, external.cursor)));
      expect(parallel.every((r) => !r.changed && r.cursor == external.cursor), isTrue);
      await SalonDatabase.instance.close();
      await SalonDatabase.instance.initialize(preserveExistingTestDatabase: true);
      final restart = await source.read(external.epoch, external.cursor);
      expect(restart.epoch, isNot(external.epoch)); expect(restart.reset, isTrue);
      expect((await (await SalonDatabase.instance.database).rawQuery('PRAGMA user_version')).single.values.single, schema);
      expect(jsonEncode(restart.toJson()), isNot(contains('Staff changed')));
    } finally { await SalonDatabase.instance.close(); }
  });
  test('change protocol rejects oversized cursors, private records and malformed versions', () {
    const valid = LanChangeSnapshot('epoch-a', 1, reset: true, changed: true);
    expect(LanChangeSnapshot.fromJson(valid.toJson()).cursor, 1);
    for (final json in [
      {...valid.toJson(), 'apiVersion': 2}, {...valid.toJson(), 'cursor': 9007199254740992},
      {...valid.toJson(), 'cursor': 0}, {...valid.toJson(), 'epoch': 'x' * 81},
      {...valid.toJson(), 'changed': 'true'}, {...valid.toJson(), 'customers': ['private']},
    ]) { expect(() => LanChangeSnapshot.fromJson(json), throwsFormatException); }
  });
  final fixture = Platform.environment['SALON_TEST_TLS_DIR'];
  if (fixture == null) return;
  test('pinned changes reject pending/connection-only/revoked authority and in-flight revoke', () async {
    final root = await Directory.systemTemp.createTemp('salon-changes-');
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), source = _DelayedChanges();
    final port = probe.port; await probe.close();
    final config = LanHostConfig(address: InternetAddress.loopbackIPv4, port: port,
      certificatePath: '$fixture/certificate.pem', privateKeyPath: '$fixture/private-key.pem');
    final registry = LanPairingRegistry(file: File('${root.path}/devices.json'));
    final host = LanHealthHost(lockFile: File('${root.path}/backend.lock'), pairing: registry, changes: source);
    const client = PinnedLanChangeClient();
    try {
      await host.start(config);
      final connection = LanConnection(config.apiUrl.toString(), await config.certificateSha256());
      final token = newDeviceSecret();
      await expectLater(client.read(connection, token, null, 0), throwsA(isA<PairingFailure>()));
      final phone = await registry.request(await registry.createCode(), 'Phone', token);
      await expectLater(client.read(connection, token, null, 0), throwsA(isA<PairingFailure>()));
      await registry.decide(phone.id, PhoneAccess.approved);
      await expectLater(client.read(connection, token, null, 0), throwsA(isA<PairingFailure>()));
      expect(source.reads, 0);
      await registry.setReadAccess(phone.id, true);
      await expectLater(client.read(LanConnection(config.apiUrl.toString(), '0' * 64), token, null, 0),
        throwsA(isA<HandshakeException>()));
      final pending = client.read(connection, token, null, 0);
      final rejected = expectLater(pending, throwsA(isA<PairingFailure>()));
      await source.entered.future; await registry.decide(phone.id, PhoneAccess.revoked);
      source.finish.complete(); await rejected;
      await expectLater(client.read(connection, token, null, 0), throwsA(isA<PairingFailure>()));
      expect(source.reads, 1);
      final secondToken = newDeviceSecret();
      final second = await registry.request(await registry.createCode(), 'Other phone', secondToken);
      await registry.decide(second.id, PhoneAccess.approved); await registry.setReadAccess(second.id, true);
      final success = await client.read(connection, secondToken, null, 0);
      expect(success.epoch, 'epoch-a'); expect(success.cursor, 1); expect(success.reset, isTrue);
      final raw = HttpClient(context: SecurityContext(withTrustedRoots: false));
      raw.badCertificateCallback = connection.matches;
      try {
        for (final suffix in ['?cursor=0&token=secret', '?cursor=0&cursor=1', '?cursor=-1', '?cursor=0&epoch=${'x' * 81}']) {
          final request = await raw.getUrl(Uri.parse('${connection.apiUrl}/changes$suffix'));
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
          final response = await request.close(); expect(response.statusCode, 400);
          expect(response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
          final body = await utf8.decoder.bind(response).join();
          expect(body, isNot(contains(token))); expect(body, isNot(contains(root.path)));
        }
      } finally { raw.close(force: true); }
    } finally { await host.stop(); registry.dispose(); await root.delete(recursive: true); }
  });
}
