import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;

import 'offline_update_manifest.dart';
import 'offline_update_status.dart';

class OfflineUpdateService {
  const OfflineUpdateService();

  Future<OfflineUpdateStatus?> checkForUpdate(
    String configuredPath, {
    String licenseKey = '',
    String deviceId = '',
    String deviceName = '',
  }) async {
    final trimmedPath = configuredPath.trim();
    if (trimmedPath.isEmpty) {
      return null;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final manifestSource = _resolveManifestPath(
      trimmedPath,
      licenseKey: licenseKey,
      deviceId: deviceId,
      deviceName: deviceName,
      currentVersion: currentVersion,
    );
    final raw = _isRemotePath(manifestSource)
        ? await _readRemoteText(manifestSource)
        : await _readLocalText(manifestSource);
    final json = jsonDecode(raw);
    if (json is! Map<String, Object?>) {
      return null;
    }

    final resolved = _resolveManifestEnvelope(json, manifestSource);
    final manifest = resolved.manifest;
    if (manifest.latestVersion.isEmpty ||
        manifest.downloadPath.trim().isEmpty) {
      return null;
    }

    if (_compareVersions(manifest.latestVersion, currentVersion) <= 0) {
      return null;
    }

    return OfflineUpdateStatus(
      currentVersion: currentVersion,
      sourcePath: manifestSource,
      manifest: manifest,
      updateAllowed: resolved.updateAllowed,
      currentVersionSupported: resolved.currentVersionSupported,
      entitlementReason: resolved.entitlementReason,
      entitlementMessage: resolved.entitlementMessage,
    );
  }

  Future<bool> openInstaller(String installerPath) async {
    final trimmedPath = installerPath.trim();
    if (trimmedPath.isEmpty) {
      return false;
    }

    if (_isRemotePath(trimmedPath)) {
      await Process.start(
        'cmd',
        ['/c', 'start', '', trimmedPath],
        runInShell: true,
        mode: ProcessStartMode.detached,
      );
      return true;
    }

    final installerFile = File(trimmedPath);
    if (!await installerFile.exists()) {
      return false;
    }

    await Process.start(
      'cmd',
      ['/c', 'start', '', trimmedPath],
      runInShell: true,
      mode: ProcessStartMode.detached,
    );
    return true;
  }

  String _resolveManifestPath(
    String configuredPath, {
    required String licenseKey,
    required String deviceId,
    required String deviceName,
    required String currentVersion,
  }) {
    if (_isRemotePath(configuredPath) ||
        configuredPath.toLowerCase().endsWith('.json')) {
      if (!_isRemotePath(configuredPath)) {
        return configuredPath;
      }

      final uri = Uri.parse(configuredPath);
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

    return path.join(configuredPath, 'version.json');
  }

  Future<String> _readLocalText(String manifestPath) async {
    final manifestFile = File(manifestPath);
    if (!await manifestFile.exists()) {
      throw FileSystemException(
        'Không tìm thấy manifest update.',
        manifestPath,
      );
    }
    return manifestFile.readAsString();
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

  _ResolvedManifestEnvelope _resolveManifestEnvelope(
    Map<String, Object?> json,
    String sourcePath,
  ) {
    final dataNode = json['data'];
    final manifestNode = dataNode is Map<String, Object?>
        ? dataNode['manifest']
        : null;
    final entitlementNode = dataNode is Map<String, Object?>
        ? dataNode['updateEntitlement']
        : null;
    final manifestJson = manifestNode is Map<String, Object?>
        ? manifestNode
        : json;
    final sourceUri = _isRemotePath(sourcePath)
        ? Uri.tryParse(sourcePath)
        : null;

    final manifest = _normalizeManifestPaths(
      OfflineUpdateManifest.fromJson(manifestJson),
      sourceUri,
    );

    final entitlement = entitlementNode is Map<String, Object?>
        ? entitlementNode
        : const <String, Object?>{};
    final updateAllowed = entitlement['updateAllowed'] != false;
    final currentVersionAllowed = entitlement['currentVersionAllowed'];
    final currentVersionSupported = currentVersionAllowed is bool
        ? currentVersionAllowed
        : true;
    final reason = entitlement['reason']?.toString();

    String? message;
    if (updateAllowed == false) {
      if (reason == 'update_not_entitled') {
        message =
            'Key hiện tại không còn quyền nhận bản cập nhật này. Hãy gia hạn update trước khi cài.';
      } else if (reason == 'missing_license') {
        message =
            'Manifest này yêu cầu key hợp lệ để mở cập nhật. Hãy nối license key vào URL manifest hoặc dùng nguồn update nội bộ.';
      } else if (reason == 'device_mismatch') {
        message =
            'Key đang gắn với thiết bị khác, nên bản update này chưa được mở cho máy hiện tại.';
      } else if (reason == 'invalid_license') {
        message =
            'Key không hợp lệ hoặc đã bị thu hồi, nên updater không cho phép cài bản mới.';
      }
    }

    return _ResolvedManifestEnvelope(
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
    if (trimmed.isEmpty) {
      return trimmed;
    }
    if (_isRemotePath(trimmed)) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return sourceUri.resolve(trimmed).toString();
    }
    return sourceUri.resolve(trimmed).toString();
  }

  int _compareVersions(String left, String right) {
    final leftParts = _normalizeVersion(left);
    final rightParts = _normalizeVersion(right);
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var index = 0; index < length; index++) {
      final leftPart = index < leftParts.length ? leftParts[index] : 0;
      final rightPart = index < rightParts.length ? rightParts[index] : 0;

      if (leftPart != rightPart) {
        return leftPart.compareTo(rightPart);
      }
    }

    return 0;
  }

  List<int> _normalizeVersion(String input) {
    final clean = input.split('+').first.trim();
    return clean
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }
}

class _ResolvedManifestEnvelope {
  const _ResolvedManifestEnvelope({
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
