import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../database/database_bootstrap.dart';
import '../database/database_schema.dart';
import '../database/salon_database.dart';

/// Result của thao tác backup hoặc restore.
class BackupResult {
  final bool success;
  final String message;
  final String? filePath;

  const BackupResult({
    required this.success,
    required this.message,
    this.filePath,
  });
}

/// Kết quả kiểm tra một tệp SQLite trước khi dùng làm backup/restore.
class BackupValidationResult {
  final bool isValid;
  final String message;
  final int? schemaVersion;

  const BackupValidationResult({
    required this.isValid,
    required this.message,
    this.schemaVersion,
  });
}

/// Dịch vụ backup/restore cơ sở dữ liệu SQLite local cho desktop.
///
/// Backup dùng `VACUUM INTO` để tạo snapshot nhất quán ngay cả khi database
/// đang mở. Restore chỉ thay file live sau khi source và temp copy đều vượt
/// qua integrity/schema validation, đồng thời luôn tạo safety backup của dữ
/// liệu hiện tại trước khi swap.
class BackupService {
  const BackupService();

  static const _requiredSalonTables = <String>{
    'customers',
    'employees',
    'services',
    'appointments',
    'invoices',
    'invoice_items',
    'app_settings',
  };

  // ── Đường dẫn ──────────────────────────────────────────────────────────────

  /// Trả về đường dẫn tệp database đang hoạt động.
  Future<String> resolveDatabasePath() async {
    final root = _resolveDataRoot();
    return path.join(root, '.salon_manager', 'salon_manager.db');
  }

  /// Trả về thư mục chứa các bản backup.
  Future<String> resolveBackupDirectory() async {
    final root = _resolveDataRoot();
    return path.join(root, 'backups');
  }

  String _resolveDataRoot() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return path.join(Directory.systemTemp.path, 'hair_spa_manager_test_data');
    }

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA']?.trim();
      if (appData != null && appData.isNotEmpty) {
        return path.join(appData, 'HairSpaManager', 'data');
      }
    }

    if (Platform.isLinux) {
      final home = Platform.environment['HOME']?.trim();
      if (home != null && home.isNotEmpty) {
        return path.join(home, '.local', 'share', 'hair_spa_manager');
      }
    }

    if (Platform.isMacOS) {
      final home = Platform.environment['HOME']?.trim();
      if (home != null && home.isNotEmpty) {
        return path.join(
          home,
          'Library',
          'Application Support',
          'HairSpaManager',
        );
      }
    }

    return path.join(Directory.current.path, '.salon_manager_data');
  }

  // ── Backup ─────────────────────────────────────────────────────────────────

  /// Tạo snapshot SQLite nhất quán vào thư mục backup mặc định.
  Future<BackupResult> createBackup() async {
    try {
      final dbPath = await resolveDatabasePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        return const BackupResult(
          success: false,
          message: 'Không tìm thấy tệp cơ sở dữ liệu để sao lưu.',
        );
      }

      final backupPath = await _nextAvailableBackupPath(
        prefix: 'salon_manager_backup',
        timestamp: DateTime.now(),
      );

      await _createSqliteSnapshot(backupPath);
      final validation = await validateBackupFile(backupPath);
      if (!validation.isValid) {
        await _deleteFileIfExists(File(backupPath));
        return BackupResult(
          success: false,
          message: 'Bản sao lưu vừa tạo không vượt qua kiểm tra: ${validation.message}',
        );
      }

      return BackupResult(
        success: true,
        message: 'Đã tạo bản sao lưu an toàn: ${path.basename(backupPath)}',
        filePath: backupPath,
      );
    } catch (e) {
      return BackupResult(success: false, message: 'Lỗi khi tạo sao lưu: $e');
    }
  }

  /// Liệt kê các tệp backup trong thư mục mặc định, mới nhất lên đầu.
  Future<List<File>> listBackups() async {
    final backupDirPath = await resolveBackupDirectory();
    final backupDir = Directory(backupDirPath);
    if (!await backupDir.exists()) {
      return [];
    }

    final files = await backupDir
        .list()
        .where(
          (entity) =>
              entity is File &&
              path.basename(entity.path).toLowerCase().endsWith('.db') &&
              path.basename(entity.path).startsWith('salon_manager_'),
        )
        .cast<File>()
        .toList();

    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  /// Kiểm tra tệp trước khi restore.
  ///
  /// Một backup hợp lệ phải là SQLite đọc được, qua `integrity_check`, có các
  /// bảng lõi của Salon và có schema version mà app hiện tại hiểu được.
  Future<BackupValidationResult> validateBackupFile(String filePath) async {
    final trimmedPath = filePath.trim();
    if (!trimmedPath.toLowerCase().endsWith('.db')) {
      return const BackupValidationResult(
        isValid: false,
        message: 'Tệp không hợp lệ. Chỉ chấp nhận tệp .db.',
      );
    }

    final file = File(trimmedPath);
    if (!await file.exists()) {
      return const BackupValidationResult(
        isValid: false,
        message: 'Không tìm thấy tệp sao lưu.',
      );
    }

    if (await file.length() < 100) {
      return const BackupValidationResult(
        isValid: false,
        message: 'Tệp quá nhỏ để là một database SQLite hợp lệ.',
      );
    }

    await DatabaseBootstrap.ensureInitialized();
    Database? database;
    try {
      database = await openDatabase(
        trimmedPath,
        readOnly: true,
        singleInstance: false,
      );
      return await _validateOpenDatabase(database, requireCurrentSchema: false);
    } catch (e) {
      return BackupValidationResult(
        isValid: false,
        message: 'Không thể đọc database SQLite: $e',
      );
    } finally {
      await database?.close();
    }
  }

  Future<BackupValidationResult> _validateOpenDatabase(
    Database database, {
    required bool requireCurrentSchema,
  }) async {
    try {
      final integrityRows = await database.rawQuery('PRAGMA integrity_check');
      final integrityValue = integrityRows.isEmpty
          ? ''
          : integrityRows.first.values.firstOrNull?.toString().trim().toLowerCase() ?? '';
      if (integrityRows.length != 1 || integrityValue != 'ok') {
        return const BackupValidationResult(
          isValid: false,
          message: 'SQLite integrity_check không đạt.',
        );
      }

      final tableRows = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tables = tableRows
          .map((row) => row['name']?.toString())
          .whereType<String>()
          .toSet();
      final missingTables = _requiredSalonTables.difference(tables);
      if (missingTables.isNotEmpty) {
        return BackupValidationResult(
          isValid: false,
          message: 'Không đúng schema Salon. Thiếu bảng: ${missingTables.join(', ')}.',
        );
      }

      final userVersionRows = await database.rawQuery('PRAGMA user_version');
      final userVersion = _readFirstInt(userVersionRows);
      if (userVersion == null || userVersion <= 0) {
        return const BackupValidationResult(
          isValid: false,
          message: 'Không đọc được schema version của database.',
        );
      }
      if (userVersion > DatabaseSchema.version) {
        return BackupValidationResult(
          isValid: false,
          message:
              'Backup dùng schema $userVersion mới hơn schema ${DatabaseSchema.version} của ứng dụng hiện tại.',
          schemaVersion: userVersion,
        );
      }

      final settingRows = await database.query(
        'app_settings',
        columns: const ['value'],
        where: 'key = ?',
        whereArgs: const ['schema_version'],
        limit: 1,
      );
      final settingVersion = settingRows.isEmpty
          ? null
          : int.tryParse(settingRows.first['value']?.toString() ?? '');
      if (settingVersion == null || settingVersion <= 0) {
        return BackupValidationResult(
          isValid: false,
          message: 'Database Salon không có schema_version hợp lệ.',
          schemaVersion: userVersion,
        );
      }
      if (settingVersion > DatabaseSchema.version) {
        return BackupValidationResult(
          isValid: false,
          message:
              'Backup khai báo schema $settingVersion mới hơn schema ${DatabaseSchema.version} của ứng dụng hiện tại.',
          schemaVersion: settingVersion,
        );
      }

      if (requireCurrentSchema &&
          (userVersion != DatabaseSchema.version ||
              settingVersion != DatabaseSchema.version)) {
        return BackupValidationResult(
          isValid: false,
          message:
              'Database sau phục hồi chưa ở schema ${DatabaseSchema.version} hiện tại.',
          schemaVersion: userVersion,
        );
      }

      return BackupValidationResult(
        isValid: true,
        message: 'Database SQLite và schema Salon hợp lệ.',
        schemaVersion: userVersion,
      );
    } catch (e) {
      return BackupValidationResult(
        isValid: false,
        message: 'Không thể xác minh schema database: $e',
      );
    }
  }

  int? _readFirstInt(List<Map<String, Object?>> rows) {
    if (rows.isEmpty || rows.first.isEmpty) return null;
    final value = rows.first.values.first;
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  // ── Restore ────────────────────────────────────────────────────────────────

  /// Phục hồi database từ tệp backup chỉ định theo flow an toàn.
  Future<BackupResult> restoreFromBackup(String backupFilePath) async {
    final sourcePath = backupFilePath.trim();
    if (!sourcePath.toLowerCase().endsWith('.db')) {
      return const BackupResult(
        success: false,
        message: 'Tệp không hợp lệ. Chỉ chấp nhận tệp .db.',
      );
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      return const BackupResult(
        success: false,
        message: 'Không tìm thấy tệp sao lưu.',
      );
    }

    final dbPath = await resolveDatabasePath();
    if (await _pathsReferToSameFile(sourcePath, dbPath)) {
      return const BackupResult(
        success: false,
        message: 'Không thể phục hồi từ chính tệp database đang hoạt động.',
      );
    }

    // Validate source trước khi tạo safety backup hoặc chạm vào DB live.
    final sourceValidation = await validateBackupFile(sourcePath);
    if (!sourceValidation.isValid) {
      return BackupResult(
        success: false,
        message: 'Tệp sao lưu không hợp lệ: ${sourceValidation.message}',
      );
    }

    final dbFile = File(dbPath);
    final dbDir = Directory(path.dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    final hadCurrentDatabase = await dbFile.exists();
    String? safetyBackupPath;

    if (hadCurrentDatabase) {
      try {
        safetyBackupPath = await _createSafetyBackup();
      } catch (e) {
        return BackupResult(
          success: false,
          message: 'Không thể tạo bản sao lưu an toàn trước khi phục hồi: $e. Thao tác bị hủy.',
        );
      }
    }

    // Copy source vào cùng volume/thư mục với DB live để bước rename sau đó là
    // atomic trong phạm vi filesystem. Temp copy cũng được validate lần hai.
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final tmpPath = '$dbPath.restore_tmp_$nonce.db';
    final oldPath = '$dbPath.restore_old_$nonce.db';
    try {
      await sourceFile.copy(tmpPath);
      final tmpValidation = await validateBackupFile(tmpPath);
      if (!tmpValidation.isValid) {
        await _deleteFileIfExists(File(tmpPath));
        return BackupResult(
          success: false,
          message: 'Bản sao tạm không vượt qua kiểm tra: ${tmpValidation.message}',
        );
      }
    } catch (e) {
      await _deleteFileIfExists(File(tmpPath));
      return BackupResult(
        success: false,
        message: 'Không thể chuẩn bị tệp phục hồi: $e',
      );
    }

    await SalonDatabase.instance.close();

    try {
      if (hadCurrentDatabase && await dbFile.exists()) {
        await dbFile.rename(oldPath);
      }

      // Không để WAL/SHM/journal cũ còn mang tên DB live và bị SQLite mới đọc.
      await _deleteDatabaseSidecars(dbPath);
      await File(tmpPath).rename(dbPath);
    } catch (e) {
      final rollbackSucceeded = await _rollbackAfterFailedRestore(
        dbPath: dbPath,
        oldPath: oldPath,
        safetyBackupPath: safetyBackupPath,
        hadCurrentDatabase: hadCurrentDatabase,
      );
      await _deleteFileIfExists(File(tmpPath));
      return BackupResult(
        success: false,
        message: rollbackSucceeded
            ? 'Lỗi khi thay thế tệp dữ liệu: $e. Dữ liệu trước phục hồi đã được khôi phục.'
            : 'Lỗi khi thay thế tệp dữ liệu: $e. Không thể tự khôi phục DB live; hãy dùng bản pre_restore trong thư mục backup.',
      );
    }

    try {
      final restoredDatabase = await SalonDatabase.instance.initialize(
        preserveExistingTestDatabase: true,
      );
      final verification = await _validateOpenDatabase(
        restoredDatabase,
        requireCurrentSchema: true,
      );
      if (!verification.isValid) {
        throw StateError(verification.message);
      }

      await _deleteFileIfExists(File(oldPath));
      await _deleteFileIfExists(File(tmpPath));
      return const BackupResult(
        success: true,
        message: 'Đã phục hồi và xác minh dữ liệu thành công.',
      );
    } catch (e) {
      final rollbackSucceeded = await _rollbackAfterFailedRestore(
        dbPath: dbPath,
        oldPath: oldPath,
        safetyBackupPath: safetyBackupPath,
        hadCurrentDatabase: hadCurrentDatabase,
      );
      await _deleteFileIfExists(File(tmpPath));
      return BackupResult(
        success: false,
        message: rollbackSucceeded
            ? 'Database phục hồi không vượt qua kiểm tra sau khi mở: $e. Dữ liệu trước phục hồi đã được khôi phục.'
            : 'Database phục hồi không hợp lệ và không thể tự rollback: $e. Hãy dùng bản pre_restore trong thư mục backup.',
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<String> _createSafetyBackup() async {
    final safetyPath = await _nextAvailableBackupPath(
      prefix: 'salon_manager_pre_restore',
      timestamp: DateTime.now(),
    );
    await _createSqliteSnapshot(safetyPath);

    final validation = await validateBackupFile(safetyPath);
    if (!validation.isValid) {
      await _deleteFileIfExists(File(safetyPath));
      throw StateError(validation.message);
    }
    return safetyPath;
  }

  Future<void> _createSqliteSnapshot(String targetPath) async {
    final targetFile = File(targetPath);
    if (await targetFile.exists()) {
      throw StateError('Tệp backup đích đã tồn tại: $targetPath');
    }

    final database = await SalonDatabase.instance.initialize(
      preserveExistingTestDatabase: true,
    );
    final escapedTarget = targetPath.replaceAll("'", "''");
    await database.execute("VACUUM INTO '$escapedTarget'");
  }

  Future<String> _nextAvailableBackupPath({
    required String prefix,
    required DateTime timestamp,
  }) async {
    final backupDirPath = await resolveBackupDirectory();
    final backupDir = Directory(backupDirPath);
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final stamp = _formatTimestamp(timestamp);
    var candidate = path.join(backupDirPath, '${prefix}_$stamp.db');
    var suffix = 1;
    while (await File(candidate).exists()) {
      candidate = path.join(
        backupDirPath,
        '${prefix}_${stamp}_${suffix.toString().padLeft(2, '0')}.db',
      );
      suffix++;
    }
    return candidate;
  }

  String _formatTimestamp(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final mo = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final h = value.hour.toString().padLeft(2, '0');
    final mi = value.minute.toString().padLeft(2, '0');
    return '$y-$mo-${d}_$h$mi';
  }

  Future<bool> _pathsReferToSameFile(String first, String second) async {
    final firstPath = await _canonicalPath(first);
    final secondPath = await _canonicalPath(second);
    return firstPath == secondPath;
  }

  Future<String> _canonicalPath(String value) async {
    var resolved = path.normalize(path.absolute(value));
    try {
      resolved = path.normalize(await File(resolved).resolveSymbolicLinks());
    } catch (_) {
      // Nếu resolve symlink không được, normalized absolute path vẫn đủ cho
      // đường dẫn local thông thường.
    }
    return Platform.isWindows ? resolved.toLowerCase() : resolved;
  }

  Future<bool> _rollbackAfterFailedRestore({
    required String dbPath,
    required String oldPath,
    required String? safetyBackupPath,
    required bool hadCurrentDatabase,
  }) async {
    try {
      await SalonDatabase.instance.close();
      await _deleteFileIfExists(File(dbPath));
      await _deleteDatabaseSidecars(dbPath);

      if (hadCurrentDatabase) {
        var restoredPreviousData = false;
        if (safetyBackupPath != null && await File(safetyBackupPath).exists()) {
          try {
            await File(safetyBackupPath).copy(dbPath);
            restoredPreviousData = true;
          } catch (_) {
            restoredPreviousData = false;
          }
        }

        if (!restoredPreviousData) {
          final oldFile = File(oldPath);
          if (!await oldFile.exists()) {
            return false;
          }
          await oldFile.rename(dbPath);
        }
      }

      final database = await SalonDatabase.instance.initialize(
        preserveExistingTestDatabase: true,
      );
      final verification = await _validateOpenDatabase(
        database,
        requireCurrentSchema: true,
      );
      if (!verification.isValid) {
        return false;
      }

      await _deleteFileIfExists(File(oldPath));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteDatabaseSidecars(String databasePath) async {
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      await _deleteFileIfExists(File('$databasePath$suffix'));
    }
  }

  Future<void> _deleteFileIfExists(File file) async {
    if (!await file.exists()) return;
    try {
      await file.delete();
    } catch (_) {
      // Cleanup best effort; không được che lỗi nghiệp vụ chính.
    }
  }
}
