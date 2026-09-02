import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/settings_upsert_input.dart';
import 'package:salonmanager/core/repositories/sqlite_settings_repository.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';

void main() {
  test('saving business settings persists every owned field in SQLite', () async {
    SharedPreferences.setMockInitialValues({'device_id': 'persist-device'});
    await LocalSettingsStore.instance.initialize();
    addTearDown(SalonDatabase.instance.close);

    final repository = SqliteSettingsRepository(
      SalonDatabase.instance,
      LocalSettingsStore.instance,
    );
    await repository.saveLocalSettings(
      const SettingsUpsertInput(
        salonName: 'Salon Persist',
        currency: 'VND',
        appointmentReminder: 'Bật',
        offlineUpdatePath: '',
        autoCheckOfflineUpdate: 'Tắt',
        licenseKey: '',
        bankName: '',
        accountNumber: '',
        accountHolder: '',
        uploadedQrPayload: '',
        qrMode: 'both',
        transferContentTemplate: 'Mã hóa đơn + SĐT khách',
      ),
    );

    final database = await SalonDatabase.instance.database;
    final rows = await database.query(
      'app_settings',
      columns: const ['key'],
      where: "key LIKE 'business.%'",
    );
    expect(rows, hasLength(9));
  });
}
