import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'package:salonmanager/core/database/database_schema.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/services/backup_service.dart';

import 'package:salonmanager/core/models/stock_document.dart';
import 'package:salonmanager/core/repositories/stock_document_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_billing_sessions_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';
import 'support/stock_schema_fixture.dart';
import 'package:salonmanager/core/models/invoice_payment_allocation.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/core/lan/lan_write_engine.dart';

final _qaPhone = PairedPhone('a' * 64, 'QA phone', PhoneAccess.approved, DateTime.utc(2026),
  canReadSalon: true, writeRole: PhoneWriteRole.owner);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = BackupService();

  final testDataRoot = path.join(
    Directory.systemTemp.path,
    'hair_spa_manager_test_data',
  );
  final dbDir = Directory(path.join(testDataRoot, '.salon_manager'));
  final backupDir = Directory(path.join(testDataRoot, 'backups'));

  setUp(() async {
    await SalonDatabase.instance.close();
    if (await dbDir.exists()) {
      try {
        await dbDir.delete(recursive: true);
      } catch (_) {}
    }
    if (await backupDir.exists()) {
      try {
        await backupDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('createBackup tạo snapshot hợp lệ khi database vẫn đang mở', () async {
    final database = await SalonDatabase.instance.initialize();
    await _writeSetting(database, 'db6_marker', 'backup-open-value');

    final result = await service.createBackup();

    expect(result.success, isTrue, reason: result.message);
    expect(result.filePath, isNotNull);

    final backupFile = File(result.filePath!);
    expect(await backupFile.exists(), isTrue);

    final fileName = path.basename(result.filePath!);
    expect(fileName, startsWith('salon_manager_backup_'));
    expect(fileName, endsWith('.db'));
    final regex = RegExp(
      r'^salon_manager_backup_\d{4}-\d{2}-\d{2}_\d{4}(?:_\d{2})?\.db$',
    );
    expect(
      regex.hasMatch(fileName),
      isTrue,
      reason: 'Tên file không khớp pattern: $fileName',
    );

    final validation = await service.validateBackupFile(result.filePath!);
    expect(validation.isValid, isTrue, reason: validation.message);
    expect(validation.schemaVersion, DatabaseSchema.version);
    expect(
      await _readSettingFromFile(result.filePath!, 'db6_marker'),
      'backup-open-value',
    );

    // Connection live vẫn dùng được sau khi VACUUM INTO tạo snapshot.
    await _writeSetting(database, 'db6_after_backup', 'still-open');
    expect(await _readSetting(database, 'db6_after_backup'), 'still-open');
  });

  test('listBackups trả về danh sách tệp .db trong thư mục backup', () async {
    await backupDir.create(recursive: true);
    final backupFile1 = File(
      path.join(backupDir.path, 'salon_manager_backup_2026-05-01_0800.db'),
    );
    final backupFile2 = File(
      path.join(backupDir.path, 'salon_manager_backup_2026-05-05_1000.db'),
    );
    final notABackup = File(path.join(backupDir.path, 'readme.txt'));
    await backupFile1.writeAsString('fake1');
    await backupFile2.writeAsString('fake2');
    await notABackup.writeAsString('should be ignored');

    final backups = await service.listBackups();

    expect(backups.length, 2);
    expect(
      path.basename(backups.first.path),
      'salon_manager_backup_2026-05-05_1000.db',
    );
    expect(
      path.basename(backups.last.path),
      'salon_manager_backup_2026-05-01_0800.db',
    );
  });

  test('restoreFromBackup phục hồi đúng dữ liệu và giữ pre_restore', () async {
    final database = await SalonDatabase.instance.initialize();
    await _writeSetting(database, 'db6_marker', 'backup-value');

    final backupResult = await service.createBackup();
    expect(backupResult.success, isTrue, reason: backupResult.message);

    await _writeSetting(database, 'db6_marker', 'current-before-restore');
    expect(await _readSetting(database, 'db6_marker'), 'current-before-restore');

    final restoreResult = await service.restoreFromBackup(
      backupResult.filePath!,
    );

    expect(restoreResult.success, isTrue, reason: restoreResult.message);

    final restoredDatabase = await SalonDatabase.instance.database;
    expect(await _readSetting(restoredDatabase, 'db6_marker'), 'backup-value');

    final activePath = await service.resolveDatabasePath();
    expect(await _readSettingFromFile(activePath, 'db6_marker'), 'backup-value');

    final safetyFiles = await _listSafetyBackups(backupDir);
    expect(safetyFiles, hasLength(1));
    expect(
      await _readSettingFromFile(safetyFiles.single.path, 'db6_marker'),
      'current-before-restore',
    );
  });

  test('restoreFromBackup từ chối file SQLite hỏng trước khi chạm DB live', () async {
    final database = await SalonDatabase.instance.initialize();
    await _writeSetting(database, 'db6_marker', 'live-safe');

    await backupDir.create(recursive: true);
    final corrupt = File(path.join(backupDir.path, 'salon_manager_corrupt.db'));
    await corrupt.writeAsBytes(List<int>.generate(256, (index) => index % 251));

    final result = await service.restoreFromBackup(corrupt.path);

    expect(result.success, isFalse);
    expect(result.message, contains('không hợp lệ'));
    expect(await _readSetting(database, 'db6_marker'), 'live-safe');
    expect(await _listSafetyBackups(backupDir), isEmpty);
  });

  test('restoreFromBackup từ chối SQLite không phải schema Salon', () async {
    final database = await SalonDatabase.instance.initialize();
    await _writeSetting(database, 'db6_marker', 'live-schema-safe');

    await backupDir.create(recursive: true);
    final wrongSchemaPath = path.join(backupDir.path, 'other_app.db');
    final wrongDatabase = await openDatabase(
      wrongSchemaPath,
      version: 1,
      singleInstance: false,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE other_data (id INTEGER PRIMARY KEY)');
      },
    );
    await wrongDatabase.close();

    final result = await service.restoreFromBackup(wrongSchemaPath);

    expect(result.success, isFalse);
    expect(result.message.toLowerCase(), contains('schema'));
    expect(await _readSetting(database, 'db6_marker'), 'live-schema-safe');
    expect(await _listSafetyBackups(backupDir), isEmpty);
  });

  test('restoreFromBackup từ chối backup có schema mới hơn ứng dụng', () async {
    final database = await SalonDatabase.instance.initialize();
    await _writeSetting(database, 'db6_marker', 'live-future-safe');

    final backupResult = await service.createBackup();
    expect(backupResult.success, isTrue, reason: backupResult.message);

    final futureVersion = DatabaseSchema.version + 1;
    final futureDatabase = await openDatabase(
      backupResult.filePath!,
      singleInstance: false,
    );
    await futureDatabase.execute('PRAGMA user_version = $futureVersion');
    await futureDatabase.update(
      'app_settings',
      {
        'value': futureVersion.toString(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'key = ?',
      whereArgs: const ['schema_version'],
    );
    await futureDatabase.close();

    final result = await service.restoreFromBackup(backupResult.filePath!);

    expect(result.success, isFalse);
    expect(result.message, contains('mới hơn'));
    expect(await _readSetting(database, 'db6_marker'), 'live-future-safe');
    expect(await _listSafetyBackups(backupDir), isEmpty);
  });

  test('restoreFromBackup không cho dùng chính database đang hoạt động', () async {
    final database = await SalonDatabase.instance.initialize();
    await _writeSetting(database, 'db6_marker', 'active-path-safe');
    final activePath = await service.resolveDatabasePath();

    final result = await service.restoreFromBackup(activePath);

    expect(result.success, isFalse);
    expect(result.message, contains('đang hoạt động'));
    expect(await _readSetting(database, 'db6_marker'), 'active-path-safe');
    expect(await _listSafetyBackups(backupDir), isEmpty);
  });

  test(
    'restoreFromBackup với tệp không tồn tại không làm mất DB hiện tại',
    () async {
      final database = await SalonDatabase.instance.initialize();
      await _writeSetting(database, 'db6_marker', 'live-missing-safe');

      final result = await service.restoreFromBackup(
        path.join(backupDir.path, 'nonexistent_backup_file.db'),
      );

      expect(result.success, isFalse);
      expect(result.message, contains('Không tìm thấy'));
      expect(await _readSetting(database, 'db6_marker'), 'live-missing-safe');
      expect(await _listSafetyBackups(backupDir), isEmpty);
    },
  );

  test('restoreFromBackup từ chối tệp không phải .db', () async {
    final database = await SalonDatabase.instance.initialize();
    await _writeSetting(database, 'db6_marker', 'live-extension-safe');

    await backupDir.create(recursive: true);
    final invalidFile = File(path.join(backupDir.path, 'data_export.csv'));
    await invalidFile.writeAsString('some,csv,data');

    final result = await service.restoreFromBackup(invalidFile.path);

    expect(result.success, isFalse);
    expect(result.message, contains('không hợp lệ'));
    expect(await _readSetting(database, 'db6_marker'), 'live-extension-safe');
    expect(await _listSafetyBackups(backupDir), isEmpty);
  });
  test('business restore and pre_restore rollback preserve documents, stock, paid and legacy bills', () async {
    final database = await SalonDatabase.instance.initialize();
    final fixture = await _seedQaBusiness(database, withDocuments: true);
    final expected = await _businessSnapshot(database);
    final epoch = SalonDatabase.instance.runtimeEpoch;
    final backup = await service.createBackup();
    expect(backup.success, isTrue, reason: backup.message);
    await database.update('customers', {'full_name': 'Sau backup'}, where: 'id = ?', whereArgs: ['qa-customer']);
    await database.update('catalog_options', {'is_active': 0}, where: 'id = ?', whereArgs: ['qa-unit']);
    final stock = StockDocumentRepository(SalonDatabase.instance, SensitiveActionService(SalonDatabase.instance));
    final posted = await stock.document('qa-receipt');
    await stock.cancel(posted.id, expectedRevision: posted.revision, reason: 'Sau backup');
    await SqliteBillingSessionsRepository(SalonDatabase.instance).addService(fixture.activeId, 'qa-service');
    final beforeRestore = await _businessSnapshot(database);
    final result = await service.restoreFromBackup(backup.filePath!);
    expect(result.success, isTrue, reason: result.message);
    final restored = await SalonDatabase.instance.database;
    expect(await _businessSnapshot(restored), expected);
    expect(SalonDatabase.instance.runtimeEpoch, isNot(epoch));
    expect(await restored.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect((await restored.query('inventory_stock')).single['stock_on_hand'], -2);
    expect((await SqliteInvoicesRepository(SalonDatabase.instance).fetchInvoiceDraft()).lines.single.quantity, 1);
    expect((await SqliteBillingSessionsRepository(SalonDatabase.instance).fetchSession(fixture.activeId)).lines.single.quantity, 2);
    final engine = LanWriteEngine(SalonDatabase.instance);
    final savedResult = await engine.result(_qaPhone.id, fixture.command.commandId);
    expect(savedResult, isNotNull);
    final replay = await engine.execute(_qaPhone, fixture.command, (_) async => throw StateError('Replay must not charge again'));
    expect(replay.id, savedResult!.id);
    expect(await _businessSnapshot(restored), expected);
    expect(await restored.query('invoice_payments'), hasLength(2));
    final preRestore = (await _listSafetyBackups(backupDir)).single;
    final safetyDb = await openDatabase(preRestore.path, readOnly: true, singleInstance: false);
    try { expect(await _businessSnapshot(safetyDb), beforeRestore); }
    finally { await safetyDb.close(); }
    final undo = await service.restoreFromBackup(preRestore.path);
    expect(undo.success, isTrue, reason: undo.message);
    expect(await _businessSnapshot(await SalonDatabase.instance.database), beforeRestore);
    await SalonDatabase.instance.close();
    expect(await _businessSnapshot(await SalonDatabase.instance.initialize(preserveExistingTestDatabase: true)), beforeRestore);
  });

  test('restore migrates real schema 19 backup preserving legacy drafts, payments, catalogs and negative history', () async {
    final database = await SalonDatabase.instance.initialize();
    final fixture = await _seedQaBusiness(database, withDocuments: false);
    await removeStockDocumentSchema(database);
    await database.setVersion(19);
    await _writeSetting(database, 'schema_version', '19');
    final legacyRows = await _businessSnapshot(database);
    final backup = await service.createBackup();
    expect(backup.success, isTrue, reason: backup.message);
    expect((await service.validateBackupFile(backup.filePath!)).schemaVersion, 19);
    await SalonDatabase.instance.close();
    final live = await SalonDatabase.instance.initialize(preserveExistingTestDatabase: true);
    await live.update('customers', {'full_name': 'Live mới'}, where: 'id = ?', whereArgs: ['qa-customer']);
    final result = await service.restoreFromBackup(backup.filePath!);
    expect(result.success, isTrue, reason: result.message);
    final upgraded = await SalonDatabase.instance.database;
    expect(await upgraded.getVersion(), DatabaseSchema.version);
    expect(await _readSetting(upgraded, 'schema_version'), DatabaseSchema.version.toString());
    for (final entry in legacyRows.entries) {
      final columns = entry.value.isEmpty ? null : entry.value.first.keys.toList();
      final rows = await upgraded.query(entry.key, columns: columns, orderBy: 'rowid',
        where: entry.key == 'app_settings' ? 'key != ?' : null,
        whereArgs: entry.key == 'app_settings' ? ['schema_version'] : null);
      expect(rows, entry.value, reason: entry.key);
    }
    expect(await upgraded.query('stock_documents'), isEmpty);
    expect(await upgraded.query('stock_suppliers'), isEmpty);
    expect((await upgraded.query('inventory_movements')).single['source'], 'legacy');
    expect((await upgraded.query('inventory_stock')).single['stock_on_hand'], -5);
    expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect((await SqliteInvoicesRepository(SalonDatabase.instance).fetchInvoiceDraft()).lines.single.quantity, 1);
    expect((await SqliteBillingSessionsRepository(SalonDatabase.instance).fetchSession(fixture.activeId)).lines.single.quantity, 2);
  });

  test('post-swap open failure rolls back all business rows and keeps safety backup', () async {
    final database = await SalonDatabase.instance.initialize();
    await _seedQaBusiness(database, withDocuments: true);
    final backup = await service.createBackup();
    expect(backup.success, isTrue, reason: backup.message);
    final source = await openDatabase(backup.filePath!, singleInstance: false);
    try {
      // Valid SQLite passes preflight, but fails production onOpen schema write.
      await source.execute("CREATE TRIGGER qa_fail_open BEFORE INSERT ON app_settings WHEN NEW.key = 'schema_version' BEGIN SELECT RAISE(ABORT, 'QA open failure'); END");
    } finally { await source.close(); }
    expect((await service.validateBackupFile(backup.filePath!)).isValid, isTrue);
    await database.update('customers', {'full_name': 'Dữ liệu cần giữ'}, where: 'id = ?', whereArgs: ['qa-customer']);
    final expected = await _businessSnapshot(database);
    final result = await service.restoreFromBackup(backup.filePath!);
    expect(result.success, isFalse);
    final rolledBack = await SalonDatabase.instance.database;
    expect(await _businessSnapshot(rolledBack), expected);
    expect(await rolledBack.rawQuery('PRAGMA integrity_check'), [{'integrity_check': 'ok'}]);
    expect(await rolledBack.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(await _listSafetyBackups(backupDir), hasLength(1));
    expect(await dbDir.list().where((entry) => entry.path.contains('.restore_')).toList(), isEmpty);
    await SalonDatabase.instance.close();
    expect(await _businessSnapshot(await SalonDatabase.instance.initialize(preserveExistingTestDatabase: true)), expected);
  });

  test('orphaned invoice backup is rejected before touching live business data', () async {
    final database = await SalonDatabase.instance.initialize();
    await _seedQaBusiness(database, withDocuments: true);
    final expected = await _businessSnapshot(database);
    final backup = await service.createBackup();
    expect(backup.success, isTrue, reason: backup.message);
    final source = await openDatabase(backup.filePath!, singleInstance: false);
    try {
      await source.execute('PRAGMA foreign_keys = OFF');
      await source.update('invoice_items', {'invoice_id': 'missing-invoice'});
      expect(await source.rawQuery('PRAGMA integrity_check'), [{'integrity_check': 'ok'}]);
      expect(await source.rawQuery('PRAGMA foreign_key_check'), isNotEmpty);
    } finally { await source.close(); }
    final result = await service.restoreFromBackup(backup.filePath!);
    expect(result.success, isFalse);
    expect(result.message, contains('foreign_key_check'));
    expect(await _businessSnapshot(database), expected);
    expect(await _listSafetyBackups(backupDir), isEmpty);
  });

}

Future<List<File>> _listSafetyBackups(Directory backupDir) async {
  if (!await backupDir.exists()) return [];
  final files = await backupDir
      .list()
      .where((entity) => entity is File)
      .cast<File>()
      .where(
        (file) => path.basename(file.path).startsWith('salon_manager_pre_restore_'),
      )
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

Future<void> _writeSetting(Database database, String key, String value) async {
  await database.insert(
    'app_settings',
    {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<String?> _readSetting(Database database, String key) async {
  final rows = await database.query(
    'app_settings',
    columns: const ['value'],
    where: 'key = ?',
    whereArgs: [key],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first['value']?.toString();
}

Future<String?> _readSettingFromFile(String filePath, String key) async {
  final database = await openDatabase(
    filePath,
    readOnly: true,
    singleInstance: false,
  );
  try {
    return await _readSetting(database, key);
  } finally {
    await database.close();
  }
}



/// Synthetic salon only; use repositories for billing and posted documents.
Future<({String activeId, LanWriteCommand command})> _seedQaBusiness(Database db, {required bool withDocuments}) async {
  const stamp = '2026-10-06T10:00:00.000';
  await db.insert('customers', {'id': 'qa-customer', 'full_name': 'Khách QA', 'phone': '0900000001', 'created_at': stamp, 'updated_at': stamp});
  await db.insert('services', {'id': 'qa-service', 'name': 'Cắt QA', 'category': 'Tóc', 'duration_minutes': 30, 'price': 100000, 'created_at': stamp, 'updated_at': stamp});
  await db.insert('catalog_options', {'id': 'qa-unit', 'kind': 'product_unit', 'name': 'Chai QA', 'normalized_name': 'chai qa', 'created_at': stamp, 'updated_at': stamp});
  await db.insert('retail_products', {'id': 'qa-product', 'name': 'Dầu QA', 'brand': 'QA', 'volume_label': '500 ml', 'product_type': 'QA',
    'unit_option_id': 'qa-unit', 'unit_name': 'Chai QA', 'sale_price': 50000, 'created_at': stamp, 'updated_at': stamp});
  await db.insert('inventory_stock', {'product_id': 'qa-product', 'stock_on_hand': -4, 'updated_at': stamp});
  await db.insert('appointments', {'id': 'qa-appointment', 'customer_id': 'qa-customer', 'service_id': 'qa-service',
    'starts_at': stamp, 'status': 'Đã đặt', 'created_at': stamp, 'updated_at': stamp});
  final bills = SqliteBillingSessionsRepository(SalonDatabase.instance);
  final paid = await bills.createWalkInSession();
  await bills.selectCustomer(paid.id, 'qa-customer');
  await bills.addProduct(paid.id, 'qa-product');
  await bills.updatePaymentAllocations(paid.id, const [
    InvoicePaymentAllocation(paymentMethod: 'Tiền mặt', amount: 20000),
    InvoicePaymentAllocation(paymentMethod: 'Chuyển khoản', amount: 30000),
  ]);
  final engine = LanWriteEngine(SalonDatabase.instance);
  final command = LanWriteCommand(commandId: 'qa-checkout', operation: LanWriteOperation.sessionCheckout,
    expectedEpoch: SalonDatabase.instance.runtimeEpoch, targetId: paid.id,
    expectedRevision: await engine.revision(db, 'session', paid.id), payload: {});
  await engine.execute(_qaPhone, command, (scope) async {
    final invoices = SqliteInvoicesRepository(scope, null, paid.id);
    await invoices.checkoutInvoice();
    return LanMutationTarget(invoices.lastArchivedInvoiceId!, 'invoice');
  });
  final active = await bills.createWalkInSession();
  await bills.selectCustomer(active.id, 'qa-customer');
  await bills.addService(active.id, 'qa-service');
  await bills.addService(active.id, 'qa-service');
  await SqliteInvoicesRepository(SalonDatabase.instance).addInvoiceService('qa-service');
  if (withDocuments) {
    final repo = StockDocumentRepository(SalonDatabase.instance, SensitiveActionService(SalonDatabase.instance));
    await repo.saveSupplier(const StockSupplier(id: 'qa-supplier', name: 'NCC QA', phone: '0900000002'));
    StockDocumentInput input(String id, int quantity) => StockDocumentInput(
      id: id, kind: StockDocumentKind.receipt, date: DateTime(2026, 10, 6),
      preparedBy: 'QA', supplierId: 'qa-supplier',
      lines: [StockDocumentLineInput(productId: 'qa-product', quantity: quantity, unitCost: 12000)]);
    final receipt = await repo.saveDraft(input('qa-receipt', 3));
    await repo.post(receipt.id, expectedRevision: receipt.revision);
    final cancelled = await repo.saveDraft(input('qa-cancelled', 1));
    final posted = await repo.post(cancelled.id, expectedRevision: cancelled.revision);
    await repo.cancel(posted.id, expectedRevision: posted.revision, reason: 'QA hủy');
    await repo.saveDraft(input('qa-draft', 2));
  }
  return (activeId: active.id, command: command);
}

/// All business/journal/audit tables; exclude only schema marker rewritten onOpen.
Future<Map<String, List<Map<String, Object?>>>> _businessSnapshot(Database db) async {
  final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
  final result = <String, List<Map<String, Object?>>>{};
  for (final table in tables) {
    final name = table['name']! as String;
    result[name] = await db.query(name, orderBy: 'rowid',
      where: name == 'app_settings' ? 'key != ?' : null,
      whereArgs: name == 'app_settings' ? ['schema_version'] : null);
  }
  return result;
}
