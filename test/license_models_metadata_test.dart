import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/license/license_models.dart';

void main() {
  test('public license snapshot parses display metadata from Key Manager', () {
    final snapshot = LicenseServerSnapshot.fromJson({
      'status': 'ACTIVE',
      'serverTime': '2026-09-10T12:00:00.000Z',
      'requestId': 'request-1',
      'application': {
        'id': 'app-salon',
        'appCode': 'SALON',
      },
      'license': {
        'id': 'license-1',
        'type': 'SUBSCRIPTION',
        'expiresAt': '2026-10-10T12:00:00.000Z',
        'maxDevices': 3,
      },
      'device': {
        'deviceId': 'device-1',
        'status': 'ACTIVE',
        'activatedAt': '2026-09-01T08:00:00.000Z',
        'lastSeenAt': '2026-09-10T11:59:00.000Z',
      },
    });

    expect(snapshot.licenseType, 'SUBSCRIPTION');
    expect(snapshot.licenseExpiresAt, DateTime.utc(2026, 10, 10, 12));
    expect(snapshot.maxDevices, 3);
    expect(snapshot.deviceActivatedAt, DateTime.utc(2026, 9, 1, 8));
    expect(snapshot.deviceLastSeenAt, DateTime.utc(2026, 9, 10, 11, 59));
  });

  test('stored schema v1 remains compatible when display metadata is absent', () {
    final state = StoredLicenseState.fromJson({
      'schemaVersion': 1,
      'licenseKey': 'SALON-VALID-KEY',
      'licenseId': 'license-1',
      'applicationId': 'app-salon',
      'deviceId': 'device-1',
      'offlineToken': null,
      'serverTimeAtSync': '2026-09-10T12:00:00.000Z',
      'wallClockAtSync': '2026-09-10T12:00:00.000Z',
      'trustedHighWater': '2026-09-10T12:00:00.000Z',
    });

    expect(state.licenseType, isNull);
    expect(state.licenseExpiresAt, isNull);
    expect(state.maxDevices, isNull);
    expect(state.deviceName, isNull);
  });

  test('stored metadata survives json round trip', () {
    final state = StoredLicenseState(
      licenseKey: 'SALON-VALID-KEY',
      licenseId: 'license-1',
      applicationId: 'app-salon',
      deviceId: 'device-1',
      licenseType: 'PERPETUAL',
      maxDevices: 2,
      deviceName: 'Salon PC',
      deviceActivatedAt: DateTime.utc(2026, 9, 1, 8),
      deviceLastSeenAt: DateTime.utc(2026, 9, 10, 11, 59),
      serverTimeAtSync: DateTime.utc(2026, 9, 10, 12),
      wallClockAtSync: DateTime.utc(2026, 9, 10, 12),
      trustedHighWater: DateTime.utc(2026, 9, 10, 12),
    );

    final restored = StoredLicenseState.fromJson(state.toJson());

    expect(restored.licenseType, 'PERPETUAL');
    expect(restored.maxDevices, 2);
    expect(restored.deviceName, 'Salon PC');
    expect(restored.deviceActivatedAt, DateTime.utc(2026, 9, 1, 8));
  });
}
