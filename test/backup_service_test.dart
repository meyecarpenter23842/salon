import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = BackupService();

  // Thư mục test dùng temp của hệ thống (FLUTTER_TEST env được set bởi flutter test)
  final testDataRoot = path.join(
    Directory.systemTemp.path,
    'hair_spa_manager_test_data',
  );
  final dbDir = Directory(path.join(testDataRoot, '.salon_manager'));
  final backupDir = Directory(path.join(testDataRoot, 'backups'));

  Future<File> createFakeDb() async {
    await SalonDatabase.instance.initialize();
    await SalonDatabase.instance.close();
    final dbPath = await service.resolveDatabasePath();
    return File(dbPath);
  }

  setUp(() async {
    await SalonDatabase.instance.close();
    // Dọn sạch thư mục test trước mỗi test
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

  test('createBackup tạo tệp backup với tên hợp lệ có timestamp', () async {
    await createFakeDb();

    final result = await service.createBackup();

    expect(result.success, isTrue, reason: result.message);
    expect(result.filePath, isNotNull);

    final backupFile = File(result.filePath!);
    expect(await backupFile.exists(), isTrue);

    final fileName = path.basename(result.filePath!);
    // Tên phải bắt đầu bằng salon_manager_backup_ và kết thúc bằng .db
    expect(fileName, startsWith('salon_manager_backup_'));
    expect(fileName, endsWith('.db'));
    // Phải có dạng salon_manager_backup_YYYY-MM-DD_HHmm.db
    final regex = RegExp(r'^salon_manager_backup_\d{4}-\d{2}-\d{2}_\d{4}\.db$');
    expect(
      regex.hasMatch(fileName),
      isTrue,
      reason: 'Tên file không khớp pattern: $fileName',
    );
  });

  test('listBackups trả về danh sách tệp .db trong thư mục backup', () async {
    // Tạo thủ công một số file backup giả
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
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
    // Mới nhất (2026-05-05) phải được trả về trước
    expect(
      path.basename(backups.first.path),
      'salon_manager_backup_2026-05-05_1000.db',
    );
    expect(
      path.basename(backups.last.path),
      'salon_manager_backup_2026-05-01_0800.db',
    );
  });

  test('restoreFromBackup phục hồi nội dung từ tệp backup hợp lệ', () async {
    // Tạo DB ban đầu và backup
    await createFakeDb();
    final backupResult = await service.createBackup();
    expect(backupResult.success, isTrue, reason: backupResult.message);

    // Ghi đè DB bằng nội dung khác để giả lập dữ liệu mới
    final dbPath = await service.resolveDatabasePath();
    await File(dbPath).writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8]);

    // Phục hồi từ backup
    final restoreResult = await service.restoreFromBackup(
      backupResult.filePath!,
    );

    expect(restoreResult.success, isTrue, reason: restoreResult.message);

    // DB sau restore phải mở được và đọc schema/settings bình thường.
    final db = await SalonDatabase.instance.initialize();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM app_settings',
    );
    final total = rows.first['total'] as int? ?? 0;
    expect(total, greaterThan(0));
    await SalonDatabase.instance.close();
  });

  test(
    'restoreFromBackup với tệp không tồn tại không làm mất DB hiện tại',
    () async {
      await createFakeDb();

      final dbPath = await service.resolveDatabasePath();
      final originalBytes = await File(dbPath).readAsBytes();

      final result = await service.restoreFromBackup(
        path.join(backupDir.path, 'nonexistent_backup_file.db'),
      );

      expect(result.success, isFalse);
      expect(result.message, contains('Không tìm thấy'));

      // DB hiện tại phải còn nguyên
      final currentBytes = await File(dbPath).readAsBytes();
      expect(currentBytes, orderedEquals(originalBytes));
    },
  );

  test('restoreFromBackup từ chối tệp không phải .db', () async {
    // Tạo file với extension sai
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    final invalidFile = File(path.join(backupDir.path, 'data_export.csv'));
    await invalidFile.writeAsString('some,csv,data');

    final result = await service.restoreFromBackup(invalidFile.path);

    expect(result.success, isFalse);
    expect(result.message, contains('không hợp lệ'));
  });
}
