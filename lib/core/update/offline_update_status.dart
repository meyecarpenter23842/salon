import 'offline_update_manifest.dart';

class OfflineUpdateStatus {
  const OfflineUpdateStatus({
    required this.currentVersion,
    required this.sourcePath,
    required this.manifest,
    required this.updateAllowed,
    required this.currentVersionSupported,
    this.entitlementReason,
    this.entitlementMessage,
  });

  final String currentVersion;
  final String sourcePath;
  final OfflineUpdateManifest manifest;
  final bool updateAllowed;
  final bool currentVersionSupported;
  final String? entitlementReason;
  final String? entitlementMessage;
}
