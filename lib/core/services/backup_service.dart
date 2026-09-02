import 'dart:io';

import 'package:path/path.dart' as path;

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

/// Dịch vụ backup/restore cơ sở dữ liệu SQLite local cho Windows desktop.
///
/// Backup: copy file .db hiện tại vào thư mục backup có tên timestamp.
/// Restore: copy file backup về đúng vị trí DB, đóng/mở lại kết nối an toàn.
class BackupService {
  const BackupService();

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

  /// Tạo bản sao lưu vào thư mục backup mặc định với tên có timestamp.
  ///
  /// Trả về [BackupResult] kèm đường dẫn tệp vừa tạo nếu thành công.
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

      final backupDirPath = await resolveBackupDirectory();
      final backupDir = Directory(backupDirPath);
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final ts = DateTime.now();
      final fileName = _buildBackupFileName(ts);
      final backupPath = path.join(backupDirPath, fileName);

      await dbFile.copy(backupPath);

      return BackupResult(
        success: true,
        message: 'Đã tạo bản sao lưu: $fileName',
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
              path.basename(entity.path).endsWith('.db') &&
              path.basename(entity.path).startsWith('salon_manager_'),
        )
        .cast<File>()
        .toList();

    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  // ── Restore ────────────────────────────────────────────────────────────────

  /// Phục hồi database từ tệp backup chỉ định.
  ///
  /// Trình tự an toàn:
  /// 1. Kiểm tra tệp nguồn hợp lệ (.db, tồn tại).
  /// 2. Tạo auto-safety backup của DB hiện tại.
  /// 3. Copy tệp nguồn vào vị trí tạm (`.restore_tmp`).
  /// 4. Đóng database connection.
  /// 5. Đổi tên DB hiện tại → `.old`, đổi tên `.restore_tmp` → DB path.
  /// 6. Xóa `.old`. Mở lại database.
  /// 7. Nếu bước 5 lỗi: khôi phục `.old` → DB path, ném lại lỗi.
  Future<BackupResult> restoreFromBackup(String backupFilePath) async {
    if (!backupFilePath.trim().endsWith('.db')) {
      return const BackupResult(
        success: false,
        message: 'Tệp không hợp lệ. Chỉ chấp nhận tệp .db.',
      );
    }

    final sourceFile = File(backupFilePath);
    if (!await sourceFile.exists()) {
      return const BackupResult(
        success: false,
        message: 'Không tìm thấy tệp sao lưu.',
      );
    }

    final dbPath = await resolveDatabasePath();
    final dbFile = File(dbPath);

    // Đảm bảo thư mục DB tồn tại
    final dbDir = Directory(path.dirname(dbPath));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    // Tạo auto-safety backup trước khi thay đổi bất cứ thứ gì
    if (await dbFile.exists()) {
      try {
        final safetyResult = await _createSafetyBackup(dbFile);
        if (!safetyResult) {
          return const BackupResult(
            success: false,
            message:
                'Không thể tạo bản sao lưu an toàn trước khi phục hồi. Thao tác bị hủy.',
          );
        }
      } catch (e) {
        return BackupResult(
          success: false,
          message: 'Lỗi khi tạo sao lưu an toàn: $e. Thao tác bị hủy.',
        );
      }
    }

    // Copy source → temp file (nếu fail: db chưa bị đụng vào)
    final tmpPath = '$dbPath.restore_tmp';
    try {
      await sourceFile.copy(tmpPath);
    } catch (e) {
      return BackupResult(
        success: false,
        message: 'Không thể đọc tệp sao lưu: $e',
      );
    }

    // Đóng database trước khi thay thế file
    await SalonDatabase.instance.close();

    // Swap an toàn: rename DB → .old, rename .tmp → DB
    final dbOldPath = '$dbPath.old';
    try {
      if (await dbFile.exists()) {
        await dbFile.rename(dbOldPath);
      }
      await File(tmpPath).rename(dbPath);
      final oldFile = File(dbOldPath);
      if (await oldFile.exists()) {
        await oldFile.delete();
      }
    } catch (e) {
      // Rollback: khôi phục DB cũ
      final oldFile = File(dbOldPath);
      if (await oldFile.exists()) {
        try {
          await oldFile.rename(dbPath);
        } catch (_) {
          // best effort
        }
      }
      // Dọn temp
      final tmpFile = File(tmpPath);
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } catch (_) {
          // best effort
        }
      }
      // Mở lại database dù restore thất bại để app không bị crash
      await SalonDatabase.instance.initialize();
      return BackupResult(
        success: false,
        message:
            'Lỗi khi thay thế tệp dữ liệu: $e. Dữ liệu cũ được giữ nguyên.',
      );
    }

    // Mở lại database
    try {
      await SalonDatabase.instance.initialize();
    } catch (e) {
      return BackupResult(
        success: false,
        message:
            'Phục hồi tệp thành công nhưng không thể mở lại database: $e. Hãy khởi động lại ứng dụng.',
      );
    }

    return const BackupResult(
      success: true,
      message:
          'Đã phục hồi dữ liệu thành công. Vui lòng kiểm tra lại dữ liệu vừa tải.',
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _buildBackupFileName(DateTime ts) {
    final y = ts.year.toString().padLeft(4, '0');
    final mo = ts.month.toString().padLeft(2, '0');
    final d = ts.day.toString().padLeft(2, '0');
    final h = ts.hour.toString().padLeft(2, '0');
    final mi = ts.minute.toString().padLeft(2, '0');
    return 'salon_manager_backup_$y-$mo-${d}_$h$mi.db';
  }

  Future<bool> _createSafetyBackup(File dbFile) async {
    final backupDirPath = await resolveBackupDirectory();
    final backupDir = Directory(backupDirPath);
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    final ts = DateTime.now();
    final y = ts.year.toString().padLeft(4, '0');
    final mo = ts.month.toString().padLeft(2, '0');
    final d = ts.day.toString().padLeft(2, '0');
    final h = ts.hour.toString().padLeft(2, '0');
    final mi = ts.minute.toString().padLeft(2, '0');
    final safetyName = 'salon_manager_pre_restore_$y-$mo-${d}_$h$mi.db';
    await dbFile.copy(path.join(backupDirPath, safetyName));
    return true;
  }
}
