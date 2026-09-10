import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../database/salon_database.dart';
import 'backup_service.dart';
import 'offline_update_service.dart';
import 'windows_self_update_handoff.dart';

/// Safe Windows install handoff for an installer that has already been
/// downloaded and SHA-256 verified by [OfflineUpdateService].
///
/// Data safety order:
/// 1. create and validate a SQLite snapshot;
/// 2. write the post-restart marker;
/// 3. start an external helper that waits for Salon to exit;
/// 4. explicitly close the live SQLite connection;
/// 5. exit the current process;
/// 6. helper closes any Staff window normally, runs NSIS silently, waits for
///    completion, then starts the updated Salon executable.
class SafeWindowsUpdateService {
  const SafeWindowsUpdateService({
    this.backupService = const BackupService(),
    this.handoff = const WindowsSelfUpdateHandoff(),
  });

  final BackupService backupService;
  final WindowsSelfUpdateHandoff handoff;

  Future<OfflineUpdateInstallResult> installDownloadedUpdate({
    required String localInstallerPath,
    required String fromVersion,
    required String targetVersion,
  }) async {
    if (!Platform.isWindows) {
      return const OfflineUpdateInstallResult(
        success: false,
        detail: 'Cập nhật tự động hiện chỉ hỗ trợ Windows.',
      );
    }

    final installer = File(localInstallerPath.trim());
    if (!await installer.exists()) {
      return const OfflineUpdateInstallResult(
        success: false,
        detail: 'Không tìm thấy bộ cài đã tải. Hãy tải lại bản cập nhật.',
      );
    }

    final backup = await backupService.createBackup();
    if (!backup.success || (backup.filePath ?? '').trim().isEmpty) {
      await _audit(
        action: 'pre_update_backup',
        outcome: 'blocked',
        detail: backup.message,
        context: {'targetVersion': targetVersion},
      );
      return OfflineUpdateInstallResult(
        success: false,
        detail:
            'Không thể tạo bản sao lưu an toàn trước khi cập nhật. Cập nhật đã bị hủy. ${backup.message}',
      );
    }

    var handoffStarted = false;
    try {
      final executable = Platform.resolvedExecutable;
      final installDir = path.dirname(executable);
      final cacheDirectory = await _resolveUpdateCacheDirectory();
      final helper = await handoff.writeHelper(cacheDirectory);

      await _writePendingMarker(
        fromVersion: fromVersion,
        targetVersion: targetVersion,
        backupPath: backup.filePath!,
      );

      await handoff.launch(
        helper: helper,
        installer: installer,
        executable: executable,
        installDir: installDir,
        parentPid: pid,
      );
      handoffStarted = true;

      await _audit(
        action: 'safe_handoff_launch',
        outcome: 'success',
        detail:
            'Đã tạo backup và khởi động helper; helper chỉ cài sau khi Salon đóng.',
        context: {
          'fromVersion': fromVersion,
          'targetVersion': targetVersion,
          'backupPath': backup.filePath!,
          'installDir': installDir,
        },
      );

      // Close SQLite before exiting. This is the key safety difference from
      // the old flow where NSIS force-killed salonmanager.exe while DB handles
      // could still be open.
      await SalonDatabase.instance.close();

      await _audit(
        action: 'pre_update_database_close',
        outcome: 'success',
        detail: 'Đã đóng SQLite trước khi thoát Salon để cập nhật.',
        context: {'targetVersion': targetVersion},
      );

      // Mirrors Key Manager's external-helper handoff: after persistent state
      // is closed, terminate this process so the helper can replace binaries.
      exit(0);
    } catch (error) {
      await _clearPendingMarker();
      await _audit(
        action: 'safe_handoff_error',
        outcome: 'error',
        detail: error.toString(),
        context: {
          'targetVersion': targetVersion,
          'handoffStarted': '$handoffStarted',
        },
      );
      return OfflineUpdateInstallResult(
        success: false,
        detail:
            'Không thể bàn giao sang trình cập nhật an toàn. Salon chưa cài đè bản mới: $error',
      );
    }
  }

  Future<Directory> _resolveUpdateCacheDirectory() async {
    final base = Platform.environment['LOCALAPPDATA']?.trim();
    final directory = Directory(
      base != null && base.isNotEmpty
          ? path.join(base, 'HairSpaManager', 'updates', 'downloads')
          : path.join(Directory.systemTemp.path, 'hair_spa_manager', 'updates'),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _resolvePendingMarkerFile() async {
    final appData = Platform.environment['APPDATA']?.trim();
    final directory = Directory(
      appData != null && appData.isNotEmpty
          ? path.join(appData, 'HairSpaManager', 'updates')
          : path.join(Directory.systemTemp.path, 'hair_spa_manager', 'updates'),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(path.join(directory.path, 'pending_update.json'));
  }

  Future<void> _writePendingMarker({
    required String fromVersion,
    required String targetVersion,
    required String backupPath,
  }) async {
    final file = await _resolvePendingMarkerFile();
    await file.writeAsString(
      jsonEncode({
        'fromVersion': fromVersion,
        'targetVersion': targetVersion,
        'backupPath': backupPath,
        'requestedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<void> _clearPendingMarker() async {
    final file = await _resolvePendingMarkerFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _audit({
    required String action,
    required String outcome,
    required String detail,
    Map<String, String>? context,
  }) async {
    try {
      final appData = Platform.environment['APPDATA']?.trim();
      final directory = Directory(
        appData != null && appData.isNotEmpty
            ? path.join(appData, 'HairSpaManager', 'logs')
            : path.join(Directory.systemTemp.path, 'hair_spa_manager', 'logs'),
      );
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final file = File(path.join(directory.path, 'update_audit.log'));
      await file.writeAsString(
        '${jsonEncode({
          'timestampUtc': DateTime.now().toUtc().toIso8601String(),
          'action': action,
          'outcome': outcome,
          'detail': detail,
          if (context != null && context.isNotEmpty) 'context': context,
        })}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Audit logging must not create a new updater failure mode.
    }
  }
}
