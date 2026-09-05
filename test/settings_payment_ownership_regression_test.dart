import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/payment_config.dart';
import 'package:salonmanager/core/repositories/sqlite_settings_repository.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'offline_update_path': r'C:\\Salon\\Updates',
      'auto_check_offline_update': 'Tắt',
      'license_key': 'device-license',
      'device_id': 'device-43',
      'device_name': 'DESKTOP-43',
    });
    await SalonDatabase.instance.close();
    await LocalSettingsStore.instance.initialize();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('profile and payment partial saves preserve unrelated ownership groups', () async {
    final repository = SqliteSettingsRepository(
      SalonDatabase.instance,
      LocalSettingsStore.instance,
    );

    await repository.savePaymentSettings(
      bankName: 'VCB',
      accountNumber: '123456789',
      accountHolder: 'SALON TEST',
      transferContentTemplate: 'HD Mã hóa đơn',
    );
    await repository.saveSalonProfileSettings(
      salonName: 'Salon Mới',
      appointmentReminder: 'Tắt',
    );
    await repository.saveDeviceUpdateSettings(
      offlineUpdatePath: r'D:\\Salon\\Offline',
      autoCheckOfflineUpdate: 'Tắt',
      licenseKey: 'new-device-license',
    );

    var settings = await repository.fetchLocalSettings();
    expect(settings['salonName'], 'Salon Mới');
    expect(settings['currency'], 'VND');
    expect(settings['appointmentReminder'], 'Tắt');
    expect(settings['bankName'], 'VCB');
    expect(settings['accountNumber'], '123456789');
    expect(settings['accountHolder'], 'SALON TEST');
    expect(settings['transferContentTemplate'], 'HD Mã hóa đơn');
    expect(settings['offlineUpdatePath'], r'D:\\Salon\\Offline');
    expect(settings['licenseKey'], 'new-device-license');
    expect(settings['qrMode'], PaymentConfig.qrModeGenerated);
    expect(settings['uploadedQrPayload'], isEmpty);

    await repository.savePaymentSettings(
      bankName: 'MB',
      accountNumber: '987654321',
      accountHolder: 'SALON TEST',
      transferContentTemplate: 'Mã hóa đơn + SĐT khách',
    );

    settings = await repository.fetchLocalSettings();
    expect(settings['salonName'], 'Salon Mới');
    expect(settings['appointmentReminder'], 'Tắt');
    expect(settings['offlineUpdatePath'], r'D:\\Salon\\Offline');
    expect(settings['licenseKey'], 'new-device-license');
    expect(settings['bankName'], 'MB');
    expect(settings['accountNumber'], '987654321');

    final payment = await repository.fetchPaymentConfig();
    expect(payment.qrMode, PaymentConfig.qrModeGenerated);
    expect(payment.uploadedQrPayload, isEmpty);
  });
}
