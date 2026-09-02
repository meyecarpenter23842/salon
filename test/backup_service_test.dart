import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'package:salonmanager/core/database/database_schema.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/services/backup_service.dart';

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
