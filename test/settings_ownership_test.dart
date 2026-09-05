import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/payment_config.dart';
import 'package:salonmanager/core/models/settings_upsert_input.dart';
import 'package:salonmanager/core/repositories/sqlite_settings_repository.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';

void main() {
  test(
    'SQLite owns business settings while machine preferences stay local',
    () async {
      SharedPreferences.setMockInitialValues({
        'salon_name': 'Legacy Salon',
        'currency': 'VND',
        'appointment_reminder': 'Bật',
        'payment_bank_name': 'Legacy Bank',
        'payment_account_number': '111222333',
        'payment_account_holder': 'LEGACY OWNER',
        'payment_uploaded_qr_payload': 'legacy-qr',
        'payment_qr_mode': 'uploaded',
        'payment_transfer_content_template': 'Legacy content',
        'offline_update_path': r'C:\Salon\Updates',
        'auto_check_offline_update': 'Bật',
        'license_key': 'device-license',
        'device_id': 'device-test-id',
        'device_name': 'DESKTOP-TEST',
      });
      await LocalSettingsStore.instance.initialize();
      addTearDown(SalonDatabase.instance.close);

      final database = await SalonDatabase.instance.database;
      await database.insert('app_settings', {
        'key': 'business.salon_name',
        'value': 'SQLite Salon',
        'updated_at': DateTime.now().toIso8601String(),
      });

      final repository = SqliteSettingsRepository(
        SalonDatabase.instance,
        LocalSettingsStore.instance,
      );

      final migrated = await repository.fetchLocalSettings();
      expect(migrated['salonName'], 'SQLite Salon');
      expect(migrated['bankName'], 'Legacy Bank');
      expect(migrated['accountNumber'], '111222333');
      expect(migrated['offlineUpdatePath'], r'C:\Salon\Updates');
      expect(migrated['licenseKey'], 'device-license');
      expect(migrated['deviceId'], 'device-test-id');

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey('salon_name'), isFalse);
      expect(preferences.containsKey('payment_bank_name'), isFalse);
      expect(preferences.getString('offline_update_path'), r'C:\Salon\Updates');
      expect(preferences.getString('license_key'), 'device-license');
      expect(preferences.getString('device_id'), 'device-test-id');

      final marker = await database.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: const ['settings_ownership_v1'],
      );
      expect(marker, hasLength(1));

      final saved = await repository.saveLocalSettings(
        const SettingsUpsertInput(
          salonName: 'Salon Chính',
          currency: 'VND',
          appointmentReminder: 'Tắt',
          offlineUpdatePath: r'D:\Salon\OfflineUpdate',
          autoCheckOfflineUpdate: 'Tắt',
          licenseKey: 'new-device-license',
          bankName: 'VCB',
          accountNumber: '999888777',
          accountHolder: 'SALON CHINH',
          uploadedQrPayload: 'qr-payload',
          qrMode: 'both',
          transferContentTemplate: 'HD + SĐT',
        ),
      );

      expect(saved['salonName'], 'Salon Chính');
      expect(saved['appointmentReminder'], 'Tắt');
      expect(saved['bankName'], 'VCB');
      expect(saved['offlineUpdatePath'], r'D:\Salon\OfflineUpdate');

      final salonRow = await database.query(
        'app_settings',
        columns: const ['value'],
        where: 'key = ?',
        whereArgs: const ['business.salon_name'],
        limit: 1,
      );
      final bankRow = await database.query(
        'app_settings',
        columns: const ['value'],
        where: 'key = ?',
        whereArgs: const ['business.payment.bank_name'],
        limit: 1,
      );
      expect(salonRow.single['value'], 'Salon Chính');
      expect(bankRow.single['value'], 'VCB');

      expect(preferences.containsKey('salon_name'), isFalse);
      expect(preferences.containsKey('payment_bank_name'), isFalse);
      expect(
        preferences.getString('offline_update_path'),
        r'D:\Salon\OfflineUpdate',
      );
      expect(preferences.getString('license_key'), 'new-device-license');

      final payment = await repository.fetchPaymentConfig();
      expect(payment.bankName, 'VCB');
      expect(payment.accountNumber, '999888777');
      expect(payment.accountHolder, 'SALON CHINH');
      expect(payment.uploadedQrPayload, isEmpty);
      expect(payment.qrMode, PaymentConfig.qrModeGenerated);
      expect(payment.transferContentTemplate, 'HD + SĐT');
    },
  );
}
