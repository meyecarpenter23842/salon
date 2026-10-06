import 'support/stock_schema_fixture.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/database/database_schema.dart';
import 'package:salonmanager/core/database/lan_write_schema.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/lan/lan_contract.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/core/lan/lan_write_engine.dart';
import 'package:salonmanager/core/models/customer_upsert_input.dart';
import 'package:salonmanager/core/repositories/sqlite_customers_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_billing_sessions_repository.dart';
import 'package:sqflite/sqflite.dart';

const input = CustomerUpsertInput(fullName: 'Lan', phone: '0901234567',
  email: '', tier: 'Standard', favoriteService: '', hairProfile: '', note: '');
final phone = PairedPhone('a' * 64, 'Phone', PhoneAccess.approved, DateTime.utc(2026),
  canReadSalon: true, writeRole: PhoneWriteRole.owner);
Matcher failure(LanErrorCode code) =>
    throwsA(isA<PairingFailure>().having((e) => e.code, 'code', code));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async { await SalonDatabase.instance.close(); });
  tearDown(() async { await SalonDatabase.instance.close(); });

  test('domain result and journal are atomic; same command replays after restart without another customer', () async {
    final database = SalonDatabase.instance;
    await database.database;
    final engine = LanWriteEngine(database);
    final command = LanWriteCommand(commandId: 'create-1',
      operation: LanWriteOperation.customerCreate, expectedEpoch: database.runtimeEpoch,
      payload: {'fullName': 'Lan', 'phone': '0901234567'});
    Future<LanMutationTarget> create(SalonDatabase scope) async {
      final saved = await SqliteCustomersRepository(scope).saveCustomer(input);
      return LanMutationTarget(saved.id, 'customer');
    }
    final first = await engine.execute(phone, command, create);
    final retry = await engine.execute(phone, command, (_) async => throw StateError('Must not run'));
    expect(retry.id, first.id);
    final db = await database.database;
    expect(await db.query('customers'), hasLength(1));
    expect(await db.query('lan_commands'), hasLength(1));
    final originalEpoch = database.runtimeEpoch;
    await database.close();
    await database.initialize(preserveExistingTestDatabase: true);
    expect(database.runtimeEpoch, isNot(originalEpoch));
    expect((await engine.execute(phone, command, create)).id, first.id);
    expect((await engine.result(phone.id, command.commandId))!.id, first.id);
    expect(await engine.result('b' * 64, command.commandId), isNull);
    final changed = LanWriteCommand(commandId: 'create-1', operation: command.operation,
      expectedEpoch: command.expectedEpoch, payload: {'phone': 'changed'});
    await expectLater(engine.execute(phone, changed, create), failure(LanErrorCode.commandConflict));
    final oldEpochNewId = LanWriteCommand(commandId: 'create-2', operation: command.operation,
      expectedEpoch: originalEpoch, payload: command.payload);
    await expectLater(engine.execute(phone, oldEpochNewId, create), failure(LanErrorCode.revisionConflict));
  });

  test('failure after domain write rolls back customer, revision and journal; retry can commit', () async {
    final database = SalonDatabase.instance;
    final db = await database.database;
    final engine = LanWriteEngine(database);
    final command = LanWriteCommand(commandId: 'rollback-1', operation: LanWriteOperation.customerCreate,
      expectedEpoch: database.runtimeEpoch, payload: {});
    await expectLater(engine.execute(phone, command, (scope) async {
      await SqliteCustomersRepository(scope).saveCustomer(input);
      throw StateError('private SQL/path/phone must not escape');
    }), failure(LanErrorCode.businessRule));
    expect(await db.query('customers'), isEmpty);
    expect(await db.query('lan_resource_revisions'), isEmpty);
    expect(await db.query('lan_commands'), isEmpty);
    final audit = jsonEncode(await db.query('audit_events'));
    expect(audit, isNot(contains(input.phone)));
    expect(audit, isNot(contains('private SQL')));
    await engine.execute(phone, command, (scope) async {
      final c = await SqliteCustomersRepository(scope).saveCustomer(input);
      return LanMutationTarget(c.id, 'customer');
    });
    expect(await db.query('customers'), hasLength(1));
  });

  test('desktop change invalidates phone revision; simultaneous different phone edits commit once', () async {
    final database = SalonDatabase.instance;
    final db = await database.database;
    final repository = SqliteCustomersRepository(database);
    final customer = await repository.saveCustomer(input);
    final engine = LanWriteEngine(database);
    final old = await engine.revision(db, 'customer', customer.id);
    await repository.saveCustomer(input, existingId: customer.id);
    final stale = LanWriteCommand(commandId: 'stale', operation: LanWriteOperation.customerUpdate,
      expectedEpoch: database.runtimeEpoch, targetId: customer.id, expectedRevision: old, payload: {});
    await expectLater(engine.execute(phone, stale, (_) async => throw StateError('Should not execute')),
      failure(LanErrorCode.revisionConflict));
    final revision = await engine.revision(db, 'customer', customer.id);
    LanWriteCommand command(String id) => LanWriteCommand(commandId: id,
      operation: LanWriteOperation.customerUpdate, expectedEpoch: database.runtimeEpoch,
      targetId: customer.id, expectedRevision: revision, payload: {});
    Future<LanMutationTarget> update(SalonDatabase scope) async {
      await SqliteCustomersRepository(scope).saveCustomer(input, existingId: customer.id);
      return LanMutationTarget(customer.id, 'customer');
    }
    final outcomes = await Future.wait([engine.execute(phone, command('one'), update)
      .then<Object>((r) => r, onError: (Object e) => e),
      engine.execute(PairedPhone('b' * 64, 'B', PhoneAccess.approved, DateTime.utc(2026),
        canReadSalon: true, writeRole: PhoneWriteRole.staff), command('two'), update)
      .then<Object>((r) => r, onError: (Object e) => e)]);
    expect(outcomes.whereType<LanWriteResult>(), hasLength(1));
    expect(outcomes.whereType<PairingFailure>().single.code, LanErrorCode.revisionConflict);
  });

  test('empty billing state and nested existing domain transactions join command rollback', () async {
    final database = SalonDatabase.instance;
    final db = await database.database;
    final engine = LanWriteEngine(database);
    final command = LanWriteCommand(commandId: 'walkin', operation: LanWriteOperation.sessionCreate,
      expectedEpoch: database.runtimeEpoch, payload: {});
    await expectLater(engine.execute(phone, command, (scope) async {
      final bill = await SqliteBillingSessionsRepository(scope).createWalkInSession();
      expect(await engine.revision(await scope.database, 'session', bill.id), greaterThan(0));
      throw StateError('Rollback all draft state');
    }), failure(LanErrorCode.businessRule));
    expect(await db.query('invoices'), isEmpty);
    expect(await db.query('app_settings', where: 'key LIKE ?', whereArgs: ['invoice_draft_state%']), isEmpty);
    expect(await db.query('lan_resource_revisions'), isEmpty);
    final bill = await engine.execute(phone, command, (scope) async {
      final saved = await SqliteBillingSessionsRepository(scope).createWalkInSession();
      return LanMutationTarget(saved.id, 'session');
    });
    expect((await engine.execute(phone, command, (_) async => throw StateError('No second bill'))).id, bill.id);
  });

  test('write roles enforce cashier and owner actions without reading desktop Owner session', () {
    expect(LanWriteOperation.customerUpdate.allows(PhoneWriteRole.staff), isTrue);
    expect(LanWriteOperation.sessionCheckout.allows(PhoneWriteRole.staff), isFalse);
    expect(LanWriteOperation.sessionCheckout.allows(PhoneWriteRole.cashier), isTrue);
    expect(LanWriteOperation.sessionDiscount.allows(PhoneWriteRole.cashier), isFalse);
    expect(LanWriteOperation.sessionPrice.allows(PhoneWriteRole.owner), isTrue);
    for (final operation in LanWriteOperation.values) {
      expect(operation.allows(PhoneWriteRole.none), isFalse);
    }
    final unknownRole = {'commandId': 'one', 'operation': 'customerCreate',
      'expectedEpoch': 'epoch', 'targetId': null, 'expectedRevision': null, 'payload': {}, 'role': 'owner'};
    expect(() => LanWriteCommand.fromJson(unknownRole), throwsFormatException);
  });

  test('schema 16 upgrade seeds revisions without modifying business rows', () async {
    final db = await SalonDatabase.instance.database;
    await db.execute('CREATE TABLE migration_business (id TEXT PRIMARY KEY)');
    await db.insert('customers', {
      'id': 'legacy-customer', 'full_name': 'Old', 'phone': '0911111111',
      'created_at': '2026-10-05', 'updated_at': '2026-10-05',
    });
    final before = jsonEncode(await db.query('customers'));
    // Reconstruct the pre-17 metadata boundary without changing source data.
    final triggerRows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'lan_rev_%'");
    for (final row in triggerRows) { await db.execute('DROP TRIGGER ${row['name']}'); }
    await db.execute('DROP TABLE lan_commands');
    await db.execute('DROP TABLE lan_resource_revisions');
    // Reconstruct the pre-18 catalog boundary as well; a version-only downgrade
    // otherwise leaves columns that a real schema-16 file never had.
    for (final column in ['group_option_id', 'brand_option_id', 'unit_option_id', 'unit_name', 'low_stock_threshold']) {
      await db.execute('ALTER TABLE retail_products DROP COLUMN $column');
    }
    await db.execute('ALTER TABLE services DROP COLUMN group_option_id');
    await db.execute('ALTER TABLE catalog_options DROP COLUMN is_active');
    await removeStockDocumentSchema(db);
    await db.setVersion(16);
    await SalonDatabase.instance.close();
    final upgraded = await SalonDatabase.instance.initialize(preserveExistingTestDatabase: true);
    expect(await upgraded.getVersion(), DatabaseSchema.version);
    expect(jsonEncode(await upgraded.query('customers')), before);
    expect(await LanWriteEngine(SalonDatabase.instance).revision(upgraded, 'customer', 'legacy-customer'), 1);
    // Installation is repeatable without resetting an existing revision.
    for (final statement in LanWriteSchema.statements) { await upgraded.execute(statement); }
    expect(await LanWriteEngine(SalonDatabase.instance).revision(upgraded, 'customer', 'legacy-customer'), 1);
  });

  test('accepted authority completes before revoke; later commands and disabling read cannot write', () async {
    final root = await Directory.systemTemp.createTemp('salon-write-authority-');
    final registry = LanPairingRegistry(file: File('${root.path}/phones.json'));
    registry.setActive(true);
    try {
      final token = newDeviceSecret();
      final pending = await registry.request(await registry.createCode(), 'Phone', token);
      await registry.decide(pending.id, PhoneAccess.approved);
      await registry.setReadAccess(pending.id, true);
      await registry.setWriteRole(pending.id, PhoneWriteRole.cashier);
      final entered = Completer<void>();
      final release = Completer<void>();
      final command = registry.withWriteAuthority(token, LanWriteOperation.sessionCheckout, (_) async {
        entered.complete(); await release.future; return 'committed';
      });
      await entered.future;
      var revoked = false;
      final revoke = registry.decide(pending.id, PhoneAccess.revoked).then((_) => revoked = true);
      await Future<void>.delayed(Duration.zero);
      expect(revoked, isFalse);
      release.complete();
      expect(await command, 'committed');
      await revoke;
      await expectLater(registry.withWriteAuthority(token, LanWriteOperation.sessionCheckout,
        (_) async => 'must not run'), failure(LanErrorCode.forbidden));
      expect((await registry.status(token)).writeRole, PhoneWriteRole.none);
      final old = PairedPhone.fromJson({'id': 'b' * 64, 'name': 'Legacy', 'state': 'approved',
        'createdAt': '2026-10-05T00:00:00Z', 'canReadSalon': true});
      expect(old.writeRole, PhoneWriteRole.none);
    } finally { registry.dispose(); await root.delete(recursive: true); }
  });
}
