import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/license/license_api.dart';
import 'package:salonmanager/core/license/license_coordinator.dart';
import 'package:salonmanager/core/license/license_models.dart';
import 'package:salonmanager/core/license/license_storage.dart';
import 'package:salonmanager/core/license/offline_license_verifier.dart';

void main() {
  const runtime = LicenseRuntimeContext(
    deviceId: 'device-1',
    deviceName: 'Salon PC',
    os: 'Windows 11',
    appVersion: '1.8.0',
  );
  final fixedNow = DateTime.utc(2026, 9, 10, 12);

  test('first launch without local license requires activation', () async {
    final storage = _MemoryStorage();
    final api = _FakeApi(snapshot: _snapshot());
    final coordinator = LicenseCoordinator(
      api: api,
      storage: storage,
      offlineVerifier: _FakeOfflineVerifier.denied(),
      runtime: runtime,
      wallClock: () => fixedNow,
    );

    final result = await coordinator.check();

    expect(result.status, LicenseAccessStatus.activationRequired);
    expect(api.validateCalls, 0);
    expect(api.activateCalls, 0);
  });

  test('valid key activates once and stores protected activation state', () async {
    final storage = _MemoryStorage();
    final api = _FakeApi(snapshot: _snapshot());
    final coordinator = LicenseCoordinator(
      api: api,
      storage: storage,
      offlineVerifier: _FakeOfflineVerifier.denied(),
      runtime: runtime,
      wallClock: () => fixedNow,
    );

    final result = await coordinator.activate('SALON-VALID-KEY');

    expect(result.status, LicenseAccessStatus.allowedOnline);
    expect(api.activateCalls, 1);
    expect(storage.state?.licenseKey, 'SALON-VALID-KEY');
    expect(storage.state?.deviceId, runtime.deviceId);
    expect(storage.state?.licenseId, 'license-1');
    expect(storage.state?.licenseType, 'SUBSCRIPTION');
    expect(storage.state?.licenseExpiresAt, DateTime.utc(2026, 10, 10, 12));
    expect(storage.state?.maxDevices, 3);
    expect(storage.state?.deviceName, 'Salon PC');
    expect(storage.state?.deviceActivatedAt, DateTime.utc(2026, 9, 1, 8));
  });

  test('wrong application key is blocked and is not persisted', () async {
    final storage = _MemoryStorage();
    final api = _FakeApi(
      snapshot: _snapshot(),
      activateError: const LicenseApiException(
        statusCode: 403,
        code: 'WRONG_APPLICATION',
        message: 'Wrong application',
        requestId: 'request-wrong-app',
      ),
    );
    final coordinator = LicenseCoordinator(
      api: api,
      storage: storage,
      offlineVerifier: _FakeOfflineVerifier.denied(),
      runtime: runtime,
      wallClock: () => fixedNow,
    );

    final result = await coordinator.activate('OTHER-APP-KEY');

    expect(result.status, LicenseAccessStatus.blocked);
    expect(result.message, contains('không được cấp cho Salon'));
    expect(result.requestId, 'request-wrong-app');
    expect(storage.state, isNull);
  });

  test('reopen validates stored key without activating again', () async {
    final storage = _MemoryStorage(
      state: _storedState(fixedNow),
    );
    final api = _FakeApi(snapshot: _snapshot());
    final coordinator = LicenseCoordinator(
      api: api,
      storage: storage,
      offlineVerifier: _FakeOfflineVerifier.denied(),
      runtime: runtime,
      wallClock: () => fixedNow.add(const Duration(minutes: 5)),
    );

    final result = await coordinator.check();

    expect(result.status, LicenseAccessStatus.allowedOnline);
    expect(api.validateCalls, 1);
    expect(api.activateCalls, 0);
    expect(storage.state?.licenseKey, 'SALON-VALID-KEY');
  });

  test('network failure only opens when signed offline entitlement is accepted', () async {
    final storage = _MemoryStorage(state: _storedState(fixedNow));
    final api = _FakeApi(
      snapshot: _snapshot(),
      validateError: const LicenseNetworkException('offline'),
    );
    final coordinator = LicenseCoordinator(
      api: api,
      storage: storage,
      offlineVerifier: _FakeOfflineVerifier.allowed(
        fixedNow.add(const Duration(minutes: 5)),
      ),
      runtime: runtime,
      wallClock: () => fixedNow.add(const Duration(minutes: 5)),
    );

    final result = await coordinator.check();

    expect(result.status, LicenseAccessStatus.allowedOffline);
    expect(result.offlineRemaining, const Duration(minutes: 55));
    expect(
      storage.state?.trustedHighWater,
      fixedNow.add(const Duration(minutes: 5)),
    );
  });
}

LicenseServerSnapshot _snapshot() {
  return LicenseServerSnapshot(
    status: 'ACTIVE',
    serverTime: DateTime.utc(2026, 9, 10, 12),
    applicationId: 'app-salon',
    appCode: 'SALON',
    licenseId: 'license-1',
    licenseType: 'SUBSCRIPTION',
    licenseExpiresAt: DateTime.utc(2026, 10, 10, 12),
    maxDevices: 3,
    deviceId: 'device-1',
    deviceStatus: 'ACTIVE',
    deviceActivatedAt: DateTime.utc(2026, 9, 1, 8),
    deviceLastSeenAt: DateTime.utc(2026, 9, 10, 11, 59),
    requestId: 'request-1',
    offline: LicenseOfflineEntitlement(
      token: 'header.payload.signature',
      keyId: 'test-key',
      issuedAt: DateTime.utc(2026, 9, 10, 12),
      offlineValidUntil: DateTime.utc(2026, 9, 10, 13),
    ),
  );
}

StoredLicenseState _storedState(DateTime now) {
  return StoredLicenseState(
    licenseKey: 'SALON-VALID-KEY',
    licenseId: 'license-1',
    applicationId: 'app-salon',
    deviceId: 'device-1',
    offlineToken: 'header.payload.signature',
    serverTimeAtSync: now,
    wallClockAtSync: now,
    trustedHighWater: now,
  );
}

class _MemoryStorage implements LicenseStorage {
  _MemoryStorage({this.state});

  StoredLicenseState? state;

  @override
  Future<String> loadOrCreateDeviceId({String? legacyDeviceId}) async {
    return legacyDeviceId ?? 'device-1';
  }

  @override
  Future<StoredLicenseState?> readLicense() async => state;

  @override
  Future<void> writeLicense(StoredLicenseState state) async {
    this.state = state;
  }
}

class _FakeApi implements LicenseApi {
  _FakeApi({
    required this.snapshot,
    this.activateError,
    this.validateError,
  });

  final LicenseServerSnapshot snapshot;
  final Object? activateError;
  final Object? validateError;
  int activateCalls = 0;
  int validateCalls = 0;

  @override
  Future<LicenseServerSnapshot> activate({
    required String appCode,
    required String licenseKey,
    required LicenseRuntimeContext runtime,
  }) async {
    activateCalls += 1;
    final error = activateError;
    if (error != null) {
      throw error;
    }
    return snapshot;
  }

  @override
  Future<LicenseServerSnapshot> validate({
    required String appCode,
    required String licenseKey,
    required LicenseRuntimeContext runtime,
  }) async {
    validateCalls += 1;
    final error = validateError;
    if (error != null) {
      throw error;
    }
    return snapshot;
  }
}

class _FakeOfflineVerifier implements OfflineLicenseVerifier {
  _FakeOfflineVerifier._(this.result);

  factory _FakeOfflineVerifier.denied() => _FakeOfflineVerifier._(
    const OfflineLicenseCheck.denied('offline denied'),
  );

  factory _FakeOfflineVerifier.allowed(DateTime trustedHighWater) =>
      _FakeOfflineVerifier._(
        OfflineLicenseCheck.allowed(
          trustedHighWater: trustedHighWater,
          remaining: const Duration(minutes: 55),
        ),
      );

  final OfflineLicenseCheck result;

  @override
  Future<OfflineLicenseCheck> verify({
    required StoredLicenseState state,
    required DateTime wallClockNow,
  }) async => result;
}
