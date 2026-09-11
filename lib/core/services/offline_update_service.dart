import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;

import '../models/offline_update_manifest.dart';
import '../models/offline_update_summary.dart';

const salonUpdateFeedBaseUrl =
    'https://pub-3f0aad8b18e146eb9eb09b9529063295.r2.dev';
const salonUpdateManifestUrl = '$salonUpdateFeedBaseUrl/latest.json';

typedef UpdateDownloadProgress = void Function(double percent);

class OfflineUpdateService {
  const OfflineUpdateService();

  static const feedBaseUrl = salonUpdateFeedBaseUrl;
  static const manifestUrl = salonUpdateManifestUrl;

  Future<OfflineUpdateSummary> buildSummary({
    required String configuredPath,
    required bool autoCheckEnabled,
    bool performCheck = true,
    String licenseKey = '',
    String deviceId = '',
    String deviceName = '',
  }) async {
    // The old arguments stay in the method signature so current providers and
    // stored settings remain source-compatible. The Windows updater itself now
    // uses one fixed public R2 feed and never sends local identifiers/secrets.
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim().isEmpty
        ? '0.0.0'
        : packageInfo.version.trim();

    if (!performCheck) {
      return OfflineUpdateSummary(
        currentVersion: currentVersion,
        configuredPath: feedBaseUrl,
        manifestPath: manifestUrl,
        autoCheckEnabled: false,
        statusLabel: 'Sẵn sàng kiểm tra cập nhật',
        statusDetail:
            'Nhấn "Kiểm tra cập nhật" để đọc bản phát hành mới nhất từ R2.',
        hasUpdate: false,
        currentVersionSupported: true,
        updateAllowed: true,
      );
    }

    await _UpdateAuditLogger.instance.log(
      action: 'check_start',
      outcome: 'info',
      detail: 'Bắt đầu kiểm tra cập nhật online.',
      context: {'manifestUrl': manifestUrl},
    );

    try {
      final manifest = await _readManifest(manifestUrl);
      final hasUpdate =
          compareSalonVersions(manifest.latestVersion, currentVersion) > 0;
      final minimum = manifest.minimumSupportedVersion.trim();
      final currentVersionSupported = minimum.isEmpty ||
          compareSalonVersions(currentVersion, minimum) >= 0;

      await _UpdateAuditLogger.instance.log(
        action: 'check_done',
        outcome: hasUpdate ? 'has_update' : 'up_to_date',
        detail: hasUpdate
            ? 'Phát hiện bản ${manifest.latestVersion}.'
            : 'Không có bản mới hơn $currentVersion.',
        context: {
          'currentVersion': currentVersion,
          'latestVersion': manifest.latestVersion,
          'manifestUrl': manifestUrl,
        },
      );

      return OfflineUpdateSummary(
        currentVersion: currentVersion,
        configuredPath: feedBaseUrl,
        manifestPath: manifestUrl,
        autoCheckEnabled: false,
        statusLabel: hasUpdate
            ? 'Có bản cập nhật mới'
            : 'Salon đang là bản mới nhất',
        statusDetail: hasUpdate
            ? 'Đã phát hiện Salon ${manifest.latestVersion}. Bản đang chạy là $currentVersion.'
            : 'Không có bản mới hơn $currentVersion trên kênh cập nhật công khai.',
        hasUpdate: hasUpdate,
        currentVersionSupported: currentVersionSupported,
        updateAllowed: true,
        manifest: manifest,
      );
    } catch (error) {
      await _UpdateAuditLogger.instance.log(
        action: 'check_error',
        outcome: 'error',
        detail: error.toString(),
        context: {'manifestUrl': manifestUrl},
      );
      return OfflineUpdateSummary(
        currentVersion: currentVersion,
        configuredPath: feedBaseUrl,
        manifestPath: manifestUrl,
        autoCheckEnabled: false,
        statusLabel: 'Không kiểm tra được cập nhật',
        statusDetail:
            'Không đọc được latest.json từ kênh cập nhật công khai. Dữ liệu Salon không bị ảnh hưởng.',
        hasUpdate: false,
        currentVersionSupported: true,
        updateAllowed: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<OfflineUpdateInstallResult> downloadInstaller({
    required String installerPath,
    required String targetVersion,
    required String expectedSha256,
    UpdateDownloadProgress? onProgress,
  }) async {
    final normalizedPath = installerPath.trim();
    final normalizedExpectedHash = expectedSha256.trim().toLowerCase();

    if (!_isSecureRemotePath(normalizedPath)) {
      return const OfflineUpdateInstallResult(
        success: false,
        detail: 'Đường dẫn bộ cài phải là HTTPS hợp lệ.',
      );
    }
    if (normalizedExpectedHash.isEmpty) {
      return const OfflineUpdateInstallResult(
        success: false,
        detail:
            'Manifest thiếu SHA-256. Salon sẽ không cài gói cập nhật chưa được xác minh.',
      );
    }

    try {
      await _UpdateAuditLogger.instance.log(
        action: 'download_start',
        outcome: 'info',
        detail: 'Bắt đầu tải bộ cài.',
        context: {'source': normalizedPath, 'targetVersion': targetVersion},
      );

      final cacheDir = await _resolveUpdateCacheDirectory();
      final sourceName = _resolveInstallerFileName(normalizedPath);
      final targetFile = File(
        path.join(cacheDir.path, '${targetVersion}_$sourceName'),
      );
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      await _downloadRemoteFile(
        normalizedPath,
        targetFile,
        onProgress: onProgress,
      );

      final actualHash = await _computeFileSha256(targetFile);
      if (actualHash != normalizedExpectedHash) {
        await _UpdateAuditLogger.instance.log(
          action: 'verify_hash',
          outcome: 'mismatch',
          detail: 'SHA-256 không khớp, hủy gói cập nhật.',
          context: {
            'expectedSha256': normalizedExpectedHash,
            'actualSha256': actualHash,
            'file': targetFile.path,
          },
        );
        await targetFile.delete();
        return const OfflineUpdateInstallResult(
          success: false,
          detail:
              'Gói cập nhật không hợp lệ (SHA-256 mismatch). Vui lòng tải lại.',
        );
      }

      await _UpdateAuditLogger.instance.log(
        action: 'verify_hash',
        outcome: 'ok',
        detail: 'SHA-256 hợp lệ.',
        context: {'file': targetFile.path, 'sha256': actualHash},
      );
      onProgress?.call(100);

      return OfflineUpdateInstallResult(
        success: true,
        localInstallerPath: targetFile.path,
        detail:
            'Đã tải Hair Spa Manager $targetVersion. Sẵn sàng khởi động lại và cập nhật.',
      );
    } catch (error) {
      await _UpdateAuditLogger.instance.log(
        action: 'download_error',
        outcome: 'error',
        detail: error.toString(),
        context: {'source': normalizedPath, 'targetVersion': targetVersion},
      );
      return OfflineUpdateInstallResult(
        success: false,
        detail: 'Không thể tải bản cập nhật: $error',
      );
    }
  }

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

    try {
      await _writePendingMarker(
        fromVersion: fromVersion,
        targetVersion: targetVersion,
      );

      final installDir = path.dirname(Platform.resolvedExecutable);
      await Process.start(
        installer.path,
        [
          '/S',
          '/D=$installDir',
        ],
        mode: ProcessStartMode.detached,
      );

      await _UpdateAuditLogger.instance.log(
        action: 'install_launch',
        outcome: 'success',
        detail: 'Đã chạy installer silent để cập nhật tại thư mục hiện tại.',
        context: {
          'file': installer.path,
          'fromVersion': fromVersion,
          'targetVersion': targetVersion,
          'installDir': installDir,
        },
      );

      return OfflineUpdateInstallResult(
        success: true,
        localInstallerPath: installer.path,
        detail:
            'Hair Spa Manager sẽ đóng, cập nhật tại thư mục đang cài và tự mở lại.',
      );
    } catch (error) {
      await _clearPendingMarker();
      await _UpdateAuditLogger.instance.log(
        action: 'install_error',
        outcome: 'error',
        detail: error.toString(),
        context: {'targetVersion': targetVersion},
      );
      return OfflineUpdateInstallResult(
        success: false,
        detail: 'Không thể khởi động trình cập nhật: $error',
      );
    }
  }

  // Compatibility wrapper for any older caller. New UI intentionally uses the
  // two-step downloadInstaller -> installDownloadedUpdate flow.
  Future<OfflineUpdateInstallResult> downloadAndLaunchInstaller({
    required String installerPath,
    required String targetVersion,
    String expectedSha256 = '',
  }) {
    return downloadInstaller(
      installerPath: installerPath,
      targetVersion: targetVersion,
      expectedSha256: expectedSha256,
    );
  }

  Future<UpdateRestartResult?> consumePostRestartResult() async {
    final markerFile = await _resolvePendingMarkerFile();
    if (!await markerFile.exists()) {
      return null;
    }

    try {
      final decoded = jsonDecode(await markerFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        await markerFile.delete();
        return null;
      }
      final fromVersion = decoded['fromVersion']?.toString() ?? '';
      final targetVersion = decoded['targetVersion']?.toString() ?? '';
      final currentVersion = (await PackageInfo.fromPlatform()).version.trim();
      await markerFile.delete();

      final completed = isExpectedInstalledVersion(
        currentVersion: currentVersion,
        fromVersion: fromVersion,
        targetVersion: targetVersion,
      );

      if (completed) {
        await _UpdateAuditLogger.instance.log(
          action: 'post_restart',
          outcome: 'success',
          detail: 'Xác nhận app đã restart sang version mới.',
          context: {
            'fromVersion': fromVersion,
            'targetVersion': targetVersion,
            'currentVersion': currentVersion,
          },
        );
        return UpdateRestartResult(
          success: true,
          fromVersion: fromVersion,
          targetVersion: targetVersion,
          currentVersion: currentVersion,
          message:
              'Đã cập nhật thành công từ $fromVersion lên $currentVersion.',
        );
      }

      await _UpdateAuditLogger.instance.log(
        action: 'post_restart',
        outcome: 'not_completed',
        detail: 'Version sau restart không khớp target update.',
        context: {
          'fromVersion': fromVersion,
          'targetVersion': targetVersion,
          'currentVersion': currentVersion,
        },
      );
      return UpdateRestartResult(
        success: false,
        fromVersion: fromVersion,
        targetVersion: targetVersion,
        currentVersion: currentVersion,
        message:
            'Lần cập nhật trước chưa hoàn tất. App vẫn đang ở $currentVersion.',
      );
    } catch (_) {
      await _clearPendingMarker();
      return null;
    }
  }

  Future<OfflineUpdateManifest> _readManifest(String manifestUrl) async {
    final raw = await _readRemoteText(manifestUrl);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('latest.json phải là JSON object hợp lệ.');
    }

    final manifest = _normalizeManifestPaths(
      OfflineUpdateManifest.fromJson(decoded),
      Uri.parse(manifestUrl),
    );
    if (manifest.latestVersion.trim().isEmpty ||
        manifest.downloadPath.trim().isEmpty ||
        manifest.sha256.trim().isEmpty) {
      throw const FormatException(
        'latest.json thiếu latestVersion, downloadPath hoặc sha256.',
      );
    }
    if (!_isSecureRemotePath(manifest.downloadPath)) {
      throw const FormatException('downloadPath của updater phải dùng HTTPS.');
    }
    return manifest;
  }

  OfflineUpdateManifest _normalizeManifestPaths(
    OfflineUpdateManifest manifest,
    Uri sourceUri,
  ) {
    return OfflineUpdateManifest(
      latestVersion: manifest.latestVersion,
      minimumSupportedVersion: manifest.minimumSupportedVersion,
      required: manifest.required,
      title: manifest.title,
      message: manifest.message,
      notes: manifest.notes,
      downloadPath: _resolveRemoteAssetPath(manifest.downloadPath, sourceUri),
      releaseNotesPath: _resolveRemoteAssetPath(
        manifest.releaseNotesPath,
        sourceUri,
      ),
      publishedAt: manifest.publishedAt,
      sha256: manifest.sha256,
    );
  }

  String _resolveRemoteAssetPath(String value, Uri sourceUri) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) return parsed.toString();
    return sourceUri.resolve(trimmed).toString();
  }

  Future<String> _readRemoteText(String manifestUrl) async {
    final uri = Uri.parse(manifestUrl);
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Tải manifest thất bại với mã ${response.statusCode}.',
          uri: uri,
        );
      }
      return utf8.decode(await response.fold<List<int>>(<int>[], (all, chunk) {
        all.addAll(chunk);
        return all;
      }));
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _downloadRemoteFile(
    String sourceUrl,
    File targetFile, {
    UpdateDownloadProgress? onProgress,
  }) async {
    final uri = Uri.parse(sourceUrl);
    final client = HttpClient();
    IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Tải bộ cài thất bại với mã ${response.statusCode}.',
          uri: uri,
        );
      }

      sink = targetFile.openWrite();
      final total = response.contentLength;
      var transferred = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        transferred += chunk.length;
        if (total > 0) {
          onProgress?.call(
            (transferred * 100 / total).clamp(0, 100).toDouble(),
          );
        }
      }
      await sink.flush();
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }

  Future<String> _computeFileSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase();
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
  }) async {
    final file = await _resolvePendingMarkerFile();
    await file.writeAsString(
      jsonEncode({
        'fromVersion': fromVersion,
        'targetVersion': targetVersion,
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

  bool _isSecureRemotePath(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  String _resolveInstallerFileName(String rawPath) {
    final uri = Uri.tryParse(rawPath);
    final candidate = uri == null ? '' : path.basename(uri.path);
    return candidate.trim().isEmpty ? 'Salon-Setup.exe' : candidate;
  }
}

int compareSalonVersions(String left, String right) {
  final a = _parseSalonVersion(left);
  final b = _parseSalonVersion(right);
  final maxLength = a.length > b.length ? a.length : b.length;

  for (var index = 0; index < maxLength; index++) {
    final aPart = index < a.length ? a[index] : 0;
    final bPart = index < b.length ? b[index] : 0;
    if (aPart != bPart) {
      return aPart.compareTo(bPart);
    }
  }
  return 0;
}

List<int> _parseSalonVersion(String value) {
  final clean = value.split('+').first.trim();
  return clean
      .split('.')
      .map((part) => int.tryParse(part.trim()) ?? 0)
      .toList(growable: false);
}

bool isExpectedInstalledVersion({
  required String currentVersion,
  required String fromVersion,
  required String targetVersion,
}) {
  return currentVersion.trim() == targetVersion.trim() &&
      currentVersion.trim() != fromVersion.trim();
}

class UpdateRestartResult {
  const UpdateRestartResult({
    required this.success,
    required this.fromVersion,
    required this.targetVersion,
    required this.currentVersion,
    required this.message,
  });

  final bool success;
  final String fromVersion;
  final String targetVersion;
  final String currentVersion;
  final String message;
}

class OfflineUpdateInstallResult {
  const OfflineUpdateInstallResult({
    required this.success,
    required this.detail,
    this.localInstallerPath,
  });

  final bool success;
  final String detail;
  final String? localInstallerPath;
}

class _UpdateAuditLogger {
  _UpdateAuditLogger._();

  static final _UpdateAuditLogger instance = _UpdateAuditLogger._();

  Future<void> log({
    required String action,
    required String outcome,
    required String detail,
    Map<String, String>? context,
  }) async {
    try {
      final payload = <String, Object?>{
        'timestampUtc': DateTime.now().toUtc().toIso8601String(),
        'action': action,
        'outcome': outcome,
        'detail': detail,
        if (context != null && context.isNotEmpty) 'context': context,
      };
      final file = await _resolveLogFile();
      await file.writeAsString(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Logging must never block the updater.
    }
  }

  Future<File> _resolveLogFile() async {
    final appData = Platform.environment['APPDATA']?.trim();
    final baseDir = Directory(
      appData != null && appData.isNotEmpty
          ? path.join(appData, 'HairSpaManager', 'logs')
          : path.join(Directory.systemTemp.path, 'hair_spa_manager', 'logs'),
    );
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    return File(path.join(baseDir.path, 'update_audit.log'));
  }
}
