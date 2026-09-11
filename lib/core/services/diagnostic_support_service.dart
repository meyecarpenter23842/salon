import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;

import '../database/database_schema.dart';
import 'backup_service.dart';
import 'offline_update_service.dart';

class DiagnosticSnapshot {
  const DiagnosticSnapshot({
    required this.collectedAtUtc,
    required this.appVersion,
    required this.buildNumber,
    required this.operatingSystem,
    required this.operatingSystemVersion,
    required this.schemaVersion,
    required this.databasePath,
    required this.backupDirectory,
    required this.logsDirectory,
    required this.updateFeed,
  });

  final DateTime collectedAtUtc;
  final String appVersion;
  final String buildNumber;
  final String operatingSystem;
  final String operatingSystemVersion;
  final int schemaVersion;
  final String databasePath;
  final String backupDirectory;
  final String logsDirectory;
  final String updateFeed;

  String get versionLabel {
    final build = buildNumber.trim();
    return build.isEmpty ? appVersion : '$appVersion+$build';
  }

  String get systemLabel {
    final version = operatingSystemVersion.trim();
    if (version.isEmpty) return operatingSystem;
    return '$operatingSystem • $version';
  }
}

class DiagnosticExportResult {
  const DiagnosticExportResult({
    required this.success,
    required this.message,
    this.filePath,
  });

  final bool success;
  final String message;
  final String? filePath;
}

class DiagnosticActionResult {
  const DiagnosticActionResult({
    required this.success,
    required this.message,
    this.path,
  });

  final bool success;
  final String message;
  final String? path;
}

class DiagnosticSupportService {
  const DiagnosticSupportService({
    this.backupService = const BackupService(),
  });

  static const supportLogNames = <String>[
    'startup_failure.log',
    'update_audit.log',
    'self_update_helper.log',
  ];

  static const int _maxLogBytes = 64 * 1024;
  static const int _maxLogLines = 200;
  static const int _maxDiagnosticExports = 5;

  final BackupService backupService;

  Future<DiagnosticSnapshot> collectSnapshot() async {
    PackageInfo? package;
    try {
      package = await PackageInfo.fromPlatform();
    } catch (_) {
      // Diagnostics should still work when package metadata is unavailable.
    }
    final databasePath = await backupService.resolveDatabasePath();
    final backupDirectory = await backupService.resolveBackupDirectory();
    final logsDirectory = (await resolveLogsDirectory()).path;
    final packageVersion = package?.version.trim() ?? '';

    return DiagnosticSnapshot(
      collectedAtUtc: DateTime.now().toUtc(),
      appVersion: packageVersion.isEmpty ? 'Không rõ' : packageVersion,
      buildNumber: package?.buildNumber.trim() ?? '',
      operatingSystem: Platform.isWindows ? 'Windows' : Platform.operatingSystem,
      operatingSystemVersion: Platform.operatingSystemVersion.trim(),
      schemaVersion: DatabaseSchema.version,
      databasePath: databasePath,
      backupDirectory: backupDirectory,
      logsDirectory: logsDirectory,
      updateFeed: salonUpdateFeedBaseUrl,
    );
  }

  Future<Directory> resolveLogsDirectory() async {
    final appData = Platform.environment['APPDATA']?.trim();
    final directory = Directory(
      appData != null && appData.isNotEmpty
          ? path.join(appData, 'HairSpaManager', 'logs')
          : path.join(
              Directory.systemTemp.path,
              'hair_spa_manager',
              'logs',
            ),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<Map<String, String>> readSupportLogs() async {
    final directory = await resolveLogsDirectory();
    final result = <String, String>{};

    for (final name in supportLogNames) {
      result[name] = await _readBoundedLogTail(File(path.join(directory.path, name)));
    }
    return result;
  }

  Future<DiagnosticExportResult> exportDiagnosticReport() async {
    try {
      final snapshot = await collectSnapshot();
      final logs = await readSupportLogs();
      final report = composeDiagnosticReport(
        snapshot: snapshot,
        logs: logs,
        environment: Platform.environment,
      );

      final directory = await resolveLogsDirectory();
      final file = File(
        path.join(
          directory.path,
          'hair_spa_manager_diagnostic_${_timestampForFile(snapshot.collectedAtUtc)}.txt',
        ),
      );
      await file.writeAsString(report, flush: true);
      await _pruneOldDiagnosticExports(directory);

      return DiagnosticExportResult(
        success: true,
        message:
            'Đã tạo gói chẩn đoán an toàn. File không chứa database hoặc backup.',
        filePath: file.path,
      );
    } catch (error) {
      return DiagnosticExportResult(
        success: false,
        message: 'Không thể tạo gói chẩn đoán: $error',
      );
    }
  }

  Future<DiagnosticActionResult> openLogsDirectory() async {
    final directory = await resolveLogsDirectory();
    return _openDirectory(
      directory,
      successMessage: 'Đã mở thư mục log hỗ trợ.',
    );
  }

  Future<DiagnosticActionResult> openDataDirectory() async {
    final databasePath = await backupService.resolveDatabasePath();
    final directory = Directory(path.dirname(databasePath));
    return _openDirectory(
      directory,
      successMessage: 'Đã mở thư mục dữ liệu Hair Spa Manager.',
    );
  }

  Future<DiagnosticActionResult> _openDirectory(
    Directory directory, {
    required String successMessage,
  }) async {
    if (!Platform.isWindows) {
      return DiagnosticActionResult(
        success: false,
        message: 'Mở thư mục tự động hiện chỉ hỗ trợ Windows.',
        path: directory.path,
      );
    }

    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      await Process.start(
        'explorer.exe',
        [directory.path],
        mode: ProcessStartMode.detached,
      );
      return DiagnosticActionResult(
        success: true,
        message: successMessage,
        path: directory.path,
      );
    } catch (error) {
      return DiagnosticActionResult(
        success: false,
        message: 'Không thể mở thư mục: $error',
        path: directory.path,
      );
    }
  }

  Future<String> _readBoundedLogTail(File file) async {
    if (!await file.exists()) {
      return '(chưa có log)';
    }

    RandomAccessFile? handle;
    try {
      final length = await file.length();
      final start = length > _maxLogBytes ? length - _maxLogBytes : 0;
      handle = await file.open();
      await handle.setPosition(start);
      final bytes = await handle.read(_maxLogBytes);
      var text = utf8.decode(bytes, allowMalformed: true);

      if (start > 0) {
        final firstBreak = text.indexOf('\n');
        if (firstBreak >= 0 && firstBreak + 1 < text.length) {
          text = text.substring(firstBreak + 1);
        }
      }

      final lines = const LineSplitter().convert(text);
      final bounded = lines.length > _maxLogLines
          ? lines.sublist(lines.length - _maxLogLines)
          : lines;
      return bounded.isEmpty ? '(log rỗng)' : bounded.join('\n');
    } catch (error) {
      return '(không đọc được log: $error)';
    } finally {
      if (handle != null) {
        await handle.close();
      }
    }
  }

  Future<void> _pruneOldDiagnosticExports(Directory directory) async {
    final files = await directory
        .list()
        .where(
          (entity) =>
              entity is File &&
              path.basename(entity.path).startsWith(
                    'hair_spa_manager_diagnostic_',
                  ) &&
              path.extension(entity.path).toLowerCase() == '.txt',
        )
        .cast<File>()
        .toList();

    if (files.length <= _maxDiagnosticExports) return;

    final entries = <({File file, DateTime modified})>[];
    for (final file in files) {
      entries.add((file: file, modified: await file.lastModified()));
    }
    entries.sort((a, b) => b.modified.compareTo(a.modified));

    for (final entry in entries.skip(_maxDiagnosticExports)) {
      try {
        await entry.file.delete();
      } catch (_) {
        // Retention cleanup must never make diagnostic export fail.
      }
    }
  }

  String _timestampForFile(DateTime value) {
    final utc = value.toUtc();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}_'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';
  }
}

String composeDiagnosticReport({
  required DiagnosticSnapshot snapshot,
  required Map<String, String> logs,
  Map<String, String>? environment,
}) {
  final buffer = StringBuffer()
    ..writeln('Hair Spa Manager - Diagnostic Support Report')
    ..writeln('Generated UTC: ${snapshot.collectedAtUtc.toUtc().toIso8601String()}')
    ..writeln()
    ..writeln('[Application]')
    ..writeln('Version: ${snapshot.versionLabel}')
    ..writeln('OS: ${snapshot.systemLabel}')
    ..writeln('Database schema: ${snapshot.schemaVersion}')
    ..writeln('Update feed: ${snapshot.updateFeed}')
    ..writeln()
    ..writeln('[Paths]')
    ..writeln('Database: ${snapshot.databasePath}')
    ..writeln('Backup directory: ${snapshot.backupDirectory}')
    ..writeln('Logs directory: ${snapshot.logsDirectory}')
    ..writeln()
    ..writeln(
      'Safety: this report contains only technical metadata and bounded support logs.',
    )
    ..writeln(
      'SQLite databases, backups, customer records, credentials and license secrets are not attached.',
    );

  for (final name in DiagnosticSupportService.supportLogNames) {
    buffer
      ..writeln()
      ..writeln('[Log: $name]')
      ..writeln(logs[name] ?? '(chưa có log)');
  }

  return sanitizeDiagnosticText(
    buffer.toString(),
    environment: environment,
  );
}

String sanitizeDiagnosticText(
  String input, {
  Map<String, String>? environment,
}) {
  var output = input;
  final env = environment ?? const <String, String>{};

  final replacements = <({String key, String value})>[];
  for (final key in const [
    'APPDATA',
    'LOCALAPPDATA',
    'USERPROFILE',
    'HOME',
    'TEMP',
    'TMP',
  ]) {
    final value = env[key]?.trim();
    if (value != null && value.isNotEmpty) {
      replacements.add((key: key, value: value));
    }
  }
  replacements.sort((a, b) => b.value.length.compareTo(a.value.length));

  for (final item in replacements) {
    output = output.replaceAll(
      RegExp(RegExp.escape(item.value), caseSensitive: false),
      '%${item.key}%',
    );
  }

  final jsonLikeSecret = RegExp(
    r'''("?(?:authorization|token|password|secret|license[_-]?key|apikey|api[_-]?key|account[_-]?number|customer[_-]?phone|phone|email)"?\s*:\s*)("[^"]*"|'[^']*'|[^,\r\n}]+)''',
    caseSensitive: false,
  );
  output = output.replaceAllMapped(
    jsonLikeSecret,
    (match) => '${match.group(1)}[REDACTED]',
  );

  final assignmentSecret = RegExp(
    r'''((?:authorization|token|password|secret|license[_-]?key|apikey|api[_-]?key|account[_-]?number|customer[_-]?phone|phone|email)\s*=\s*)[^\r\n]+''',
    caseSensitive: false,
  );
  output = output.replaceAllMapped(
    assignmentSecret,
    (match) => '${match.group(1)}[REDACTED]',
  );

  final emailPattern = RegExp(
    r'''[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}''',
    caseSensitive: false,
  );
  output = output.replaceAll(emailPattern, '[REDACTED_EMAIL]');

  return output;
}
