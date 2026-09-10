import 'license_models.dart';

abstract interface class LicenseStorage {
  Future<String> loadOrCreateDeviceId({String? legacyDeviceId});

  Future<StoredLicenseState?> readLicense();

  Future<void> writeLicense(StoredLicenseState state);
}
