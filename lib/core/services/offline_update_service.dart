import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;

import '../models/offline_update_manifest.dart';
import '../models/offline_update_summary.dart';

class OfflineUpdateService {
  const OfflineUpdateService();

  Future<OfflineUpdateSummary> buildSummary({
    required String configuredPath,
    required bool autoCheckEnabled,
    bool performCheck = true,
    String licenseKey = '',
    String deviceId = '',
    String deviceName = '',
  }) async {
    await _UpdateAuditLogger.instance.log(
      action: 'check_start',
      outcome: 'info',
      detail: 'Bắt đầu kiểm tra cập nhật offline.',
      context: {'configuredPath': configuredPath},
    );

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim().isEmpty
        ? '0.0.0'
        : packageInfo.version.trim();
    final normalizedPath = configuredPath.trim();

    if (normalizedPath.isEmpty) {
      await _UpdateAuditLogger.instance.log(
        action: 'check_skip',
        outcome: 'no_config',
        detail: 'Chưa cấu hình nguồn update.',
      );
      return OfflineUpdateSummary(
        currentVersion: currentVersion,
        configuredPath: normalizedPath,
        manifestPath: '',
        autoCheckEnabled: autoCheckEnabled,
        statusLabel: 'Chưa cấu hình nguồn update',
        statusDetail:
            'Hãy nhập đường dẫn thư mục chứa version.json hoặc URL manifest update.',
        hasUpdate: false,
        currentVersionSupported: true,
        updateAllowed: true,
      );
    }

    if (!performCheck) {
      await _UpdateAuditLogger.instance.log(
        action: 'check_skip',
        outcome: 'manual_mode',
        detail: 'Đang ở chế độ kiểm tra thủ công.',
      );
      return OfflineUpdateSummary(
        currentVersion: currentVersion,
        configuredPath: normalizedPath,
        manifestPath: _resolveManifestPath(
          normalizedPath,
          licenseKey: licenseKey,
          deviceId: deviceId,
          deviceName: deviceName,
          currentVersion: currentVersion,
        ),
        autoCheckEnabled: autoCheckEnabled,
        statusLabel: 'Sẵn sàng kiểm tra thủ công',
        statusDetail:
            'Nhấn "Kiểm tra cập nhật" trong Cài đặt để lấy thông tin bản mới.',
        hasUpdate: false,
        currentVersionSupported: true,
        updateAllowed: true,
      );
    }

    final manifestPath = _resolveManifestPath(
      normalizedPath,
      licenseKey: licenseKey,
      deviceId: deviceId,
      deviceName: deviceName,
      currentVersion: currentVersion,
    );

    try {
      final resolved = await _readManifest(manifestPath);
      final manifest = resolved.manifest;
      final hasUpdate =
          _compareVersions(manifest.latestVersion, currentVersion) > 0;
      final currentVersionSupported = resolved.currentVersionSupported;

      await _UpdateAuditLogger.instance.log(
        action: 'check_done',
        outcome: hasUpdate ? 'has_update' : 'up_to_date',
        detail: hasUpdate
            ? 'Phát hiện bản ${manifest.latestVersion}.'
            : 'Không có bản mới hơn $currentVersion.',
        context: {
          'currentVersion': currentVersion,
          'latestVersion': manifest.latestVersion,
          'manifestPath': manifestPath,
        },
      );

      return OfflineUpdateSummary(
        currentVersion: currentVersion,
        configuredPath: normalizedPath,
        manifestPath: manifestPath,
        autoCheckEnabled: autoCheckEnabled,
        statusLabel: hasUpdate
            ? 'Có bản cập nhật mới'
            : 'Đã đồng bộ manifest update',
        statusDetail: hasUpdate
            ? 'Đã phát hiện bản ${manifest.latestVersion}. App hiện tại đang ở $currentVersion.'
            : 'Manifest hợp lệ. Chưa có bản mới hơn $currentVersion.',
        hasUpdate: hasUpdate,
        currentVersionSupported: currentVersionSupported,
        updateAllowed: resolved.updateAllowed,
        manifest: manifest,
        entitlementReason: resolved.entitlementReason,
        entitlementMessage: resolved.entitlementMessage,
      );
    } catch (error) {
      await _UpdateAuditLogger.instance.log(
        action: 'check_error',
        outcome: 'error',
        detail: error.toString(),
        context: {'manifestPath': manifestPath},
      );
      return OfflineUpdateSummary(
        currentVersion: currentVersion,
        configuredPath: normalizedPath,
        manifestPath: manifestPath,
        autoCheckEnabled: autoCheckEnabled,
        statusLabel: 'Không đọc được manifest update',
        statusDetail:
            'Nguồn update đã cấu hình nhưng app chưa đọc được version.json.',
        hasUpdate: false,
        currentVersionSupported: true,
        updateAllowed: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<OfflineUpdateInstallResult> downloadAndLaunchInstaller({
    required String installerPath,
    required String targetVersion,
    String expectedSha256 = '',
  }) async {
    final normalizedPath = installerPath.trim();
    if (normalizedPath.isEmpty) {
      await _UpdateAuditLogger.instance.log(
        action: 'install_blocked',
        outcome: 'invalid_manifest',
        detail: 'Manifest thiếu đường dẫn bộ cài.',
      );
      return const OfflineUpdateInstallResult(
        success: false,
        detail: 'Manifest chưa có đường dẫn bộ cài hợp lệ.',
      );
    }

    try {
      await _UpdateAuditLogger.instance.log(
        action: 'download_start',
        outcome: 'info',
        detail: 'Bắt đầu tải bộ cài.',
        context: {'source': normalizedPath, 'targetVersion': targetVersion},
      );

      final cacheDir = Directory(
        path.join(Directory.systemTemp.path, 'hair_spa_manager', 'updates'),
      );
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      final sourceName = _resolveInstallerFileName(normalizedPath);
      final targetPath = path.join(
        cacheDir.path,
        '${DateTime.now().millisecondsSinceEpoch}_$sourceName',
      );
      final targetFile = File(targetPath);

      if (_isRemotePath(normalizedPath)) {
        await _downloadRemoteFile(normalizedPath, targetFile);
      } else {
        final sourceFile = File(normalizedPath);
        if (!await sourceFile.exists()) {
          return OfflineUpdateInstallResult(
            success: false,
            detail: 'Không tìm thấy bộ cài tại $normalizedPath',
          );
        }
        await sourceFile.copy(targetPath);
      }

      final normalizedExpectedHash = expectedSha256.trim().toLowerCase();
      if (normalizedExpectedHash.isNotEmpty) {
        final actualHash = await _computeFileSha256(targetFile);
        if (actualHash != normalizedExpectedHash) {
          await _UpdateAuditLogger.instance.log(
            action: 'verify_hash',
            outcome: 'mismatch',
            detail: 'SHA-256 không khớp, hủy mở installer.',
            context: {
              'expectedSha256': normalizedExpectedHash,
              'actualSha256': actualHash,
              'file': targetPath,
            },
          );
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          return const OfflineUpdateInstallResult(
            success: false,
            detail:
                'Gói cập nhật không hợp lệ (SHA-256 mismatch). Vui lòng tải lại hoặc kiểm tra nguồn phát hành.',
          );
        }

        await _UpdateAuditLogger.instance.log(
          action: 'verify_hash',
          outcome: 'ok',
          detail: 'SHA-256 hợp lệ.',
          context: {'file': targetPath, 'sha256': actualHash},
        );
      } else {
        await _UpdateAuditLogger.instance.log(
          action: 'verify_hash',
          outcome: 'skipped',
          detail: 'Manifest không cung cấp SHA-256, bỏ qua bước xác minh.',
          context: {'file': targetPath},
        );
      }

      await Process.start(
        'cmd',
        ['/c', 'start', '', targetPath],
        runInShell: true,
        mode: ProcessStartMode.detached,
      );

      await _UpdateAuditLogger.instance.log(
        action: 'install_launch',
        outcome: 'success',
        detail: 'Đã mở installer thành công.',
        context: {'file': targetPath, 'targetVersion': targetVersion},
      );

      return OfflineUpdateInstallResult(
        success: true,
        localInstallerPath: targetPath,
        detail:
            'Đã tải và mở bộ cài $targetVersion. Hãy đóng app để hoàn tất cập nhật.',
      );
    } catch (error) {
      await _UpdateAuditLogger.instance.log(
        action: 'install_error',
        outcome: 'error',
        detail: error.toString(),
        context: {'source': normalizedPath, 'targetVersion': targetVersion},
      );
      return OfflineUpdateInstallResult(
        success: false,
        detail: 'Không thể tải/cài đặt bản update: $error',
      );
    }
  }

  Future<String> _computeFileSha256(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString().toLowerCase();
  }

  String _resolveManifestPath(
    String rawPath, {
    required String licenseKey,
    required String deviceId,
    required String deviceName,
    required String currentVersion,
  }) {
    if (_isRemotePath(rawPath) ||
        rawPath.toLowerCase().endsWith('version.json')) {
      if (!_isRemotePath(rawPath)) {
        return rawPath;
      }

      final uri = Uri.parse(rawPath);
      final nextQuery = Map<String, String>.from(uri.queryParameters);
      nextQuery['appVersion'] = currentVersion;
      if (licenseKey.trim().isNotEmpty) {
        nextQuery['licenseKey'] = licenseKey.trim();
      }
      if (deviceId.trim().isNotEmpty) {
        nextQuery['deviceId'] = deviceId.trim();
      }
      if (deviceName.trim().isNotEmpty) {
        nextQuery['deviceName'] = deviceName.trim();
      }
      return uri.replace(queryParameters: nextQuery).toString();
    }

    return path.join(rawPath, 'version.json');
  }

  Future<_ResolvedOfflineUpdateSummary> _readManifest(
    String manifestPath,
  ) async {
    final raw = _isRemotePath(manifestPath)
        ? await _readRemoteText(manifestPath)
        : await _readLocalText(manifestPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Manifest update phải là JSON object hợp lệ.',
      );
    }

    final resolved = _resolveManifestEnvelope(decoded, manifestPath);
    final manifest = resolved.manifest;
    if (manifest.latestVersion.isEmpty || manifest.downloadPath.isEmpty) {
      throw const FormatException(
        'Manifest thiếu latestVersion hoặc downloadPath.',
      );
    }

    return resolved;
  }

  Future<String> _readLocalText(String manifestPath) async {
    final file = File(manifestPath);
    if (!await file.exists()) {
      throw FileSystemException(
        'Không tìm thấy file manifest update.',
        manifestPath,
      );
    }

    return file.readAsString();
  }

  Future<String> _readRemoteText(String manifestUrl) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(manifestUrl));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Tải manifest update thất bại với mã ${response.statusCode}.',
          uri: Uri.parse(manifestUrl),
        );
      }

      return utf8.decode(
        await response.fold<List<int>>(<int>[], (buffer, data) {
          buffer.addAll(data);
          return buffer;
        }),
      );
    } finally {
      client.close(force: true);
    }
  }

  bool _isRemotePath(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  String _resolveInstallerFileName(String rawPath) {
    if (_isRemotePath(rawPath)) {
      final uri = Uri.tryParse(rawPath);
      final candidate = uri == null ? '' : path.basename(uri.path);
      if (candidate.trim().isNotEmpty) {
        return candidate;
      }
      return 'salonmanager_update.exe';
    }
    return path.basename(rawPath);
  }

  Future<void> _downloadRemoteFile(String sourceUrl, File targetFile) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(sourceUrl));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Tải bộ cài thất bại với mã ${response.statusCode}.',
          uri: Uri.parse(sourceUrl),
        );
      }

      final sink = targetFile.openWrite();
      await response.forEach(sink.add);
      await sink.flush();
      await sink.close();
    } finally {
      client.close(force: true);
    }
  }

  _ResolvedOfflineUpdateSummary _resolveManifestEnvelope(
    Map<String, dynamic> json,
    String sourcePath,
  ) {
    final dataNode = json['data'];
    final manifestNode = dataNode is Map<String, dynamic>
        ? dataNode['manifest']
        : null;
    final entitlementNode = dataNode is Map<String, dynamic>
        ? dataNode['updateEntitlement']
        : null;
    final manifestJson = manifestNode is Map<String, dynamic>
        ? manifestNode
        : json;
    final sourceUri = _isRemotePath(sourcePath)
        ? Uri.tryParse(sourcePath)
        : null;

    final manifest = _normalizeManifestPaths(
      OfflineUpdateManifest.fromJson(manifestJson),
      sourceUri,
    );

    final entitlement = entitlementNode is Map<String, dynamic>
        ? entitlementNode
        : const <String, dynamic>{};
    final updateAllowed = entitlement['updateAllowed'] != false;
    final currentVersionAllowed = entitlement['currentVersionAllowed'];
    final currentVersionSupported = currentVersionAllowed is bool
        ? currentVersionAllowed
        : true;
    final reason = entitlement['reason']?.toString();

    String? message;
    if (updateAllowed == false) {
      if (reason == 'update_not_entitled') {
        message = 'Key hiện tại không còn quyền nhận bản cập nhật này.';
      } else if (reason == 'missing_license') {
        message = 'Manifest này yêu cầu key hợp lệ để mở cập nhật.';
      } else if (reason == 'device_mismatch') {
        message = 'Key đang gắn với thiết bị khác.';
      } else if (reason == 'invalid_license') {
        message = 'Key không hợp lệ hoặc đã bị thu hồi.';
      }
    }

    return _ResolvedOfflineUpdateSummary(
      manifest: manifest,
      updateAllowed: updateAllowed,
      currentVersionSupported: currentVersionSupported,
      entitlementReason: reason,
      entitlementMessage: message,
    );
  }

  OfflineUpdateManifest _normalizeManifestPaths(
    OfflineUpdateManifest manifest,
    Uri? sourceUri,
  ) {
    if (sourceUri == null) {
      return manifest;
    }

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
    if (trimmed.isEmpty || _isRemotePath(trimmed)) {
      return trimmed;
    }
    return sourceUri.resolve(trimmed).toString();
  }

  int _compareVersions(String left, String right) {
    final a = _parseVersion(left);
    final b = _parseVersion(right);
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

  List<int> _parseVersion(String value) {
    return value
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList(growable: false);
  }
}

class _ResolvedOfflineUpdateSummary {
  const _ResolvedOfflineUpdateSummary({
    required this.manifest,
    required this.updateAllowed,
    required this.currentVersionSupported,
    this.entitlementReason,
    this.entitlementMessage,
  });

  final OfflineUpdateManifest manifest;
  final bool updateAllowed;
  final bool currentVersionSupported;
  final String? entitlementReason;
  final String? entitlementMessage;
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
      final now = DateTime.now().toUtc().toIso8601String();
      final payload = <String, Object?>{
        'timestampUtc': now,
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
      // Không làm gián đoạn luồng update nếu ghi log thất bại.
    }
  }

  Future<File> _resolveLogFile() async {
    final appData = Platform.environment['APPDATA']?.trim();
    final baseDir = appData != null && appData.isNotEmpty
        ? Directory(path.join(appData, 'HairSpaManager', 'logs'))
        : Directory(
            path.join(Directory.systemTemp.path, 'hair_spa_manager', 'logs'),
          );
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    return File(path.join(baseDir.path, 'update_audit.log'));
  }
}
