import 'offline_update_manifest.dart';

class OfflineUpdateSummary {
  const OfflineUpdateSummary({
    required this.currentVersion,
    required this.configuredPath,
    required this.manifestPath,
    required this.autoCheckEnabled,
    required this.statusLabel,
    required this.statusDetail,
    required this.hasUpdate,
    required this.currentVersionSupported,
    required this.updateAllowed,
    this.manifest,
    this.errorMessage,
    this.entitlementReason,
    this.entitlementMessage,
  });

  final String currentVersion;
  final String configuredPath;
  final String manifestPath;
  final bool autoCheckEnabled;
  final String statusLabel;
  final String statusDetail;
  final bool hasUpdate;
  final bool currentVersionSupported;
  final bool updateAllowed;
  final OfflineUpdateManifest? manifest;
  final String? errorMessage;
  final String? entitlementReason;
  final String? entitlementMessage;
}
