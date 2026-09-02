import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/repository_providers.dart';
import 'offline_update_service.dart';
import 'offline_update_status.dart';

final offlineUpdateServiceProvider = Provider<OfflineUpdateService>(
  (ref) => const OfflineUpdateService(),
);

final offlineUpdateStatusProvider = FutureProvider<OfflineUpdateStatus?>((
  ref,
) async {
  final settings = await ref.watch(settingsViewProvider.future);
  final autoCheck = settings['autoCheckOfflineUpdate']?.toString() == 'Bật';
  final configuredPath = settings['offlineUpdatePath']?.toString() ?? '';
  final licenseKey = settings['licenseKey']?.toString() ?? '';
  final deviceId = settings['deviceId']?.toString() ?? '';
  final deviceName = settings['deviceName']?.toString() ?? '';

  if (!autoCheck || configuredPath.trim().isEmpty) {
    return null;
  }

  return ref
      .watch(offlineUpdateServiceProvider)
      .checkForUpdate(
        configuredPath,
        licenseKey: licenseKey,
        deviceId: deviceId,
        deviceName: deviceName,
      );
});
