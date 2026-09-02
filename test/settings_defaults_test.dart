import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/repositories/sqlite_settings_repository.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';

void main() {
  test('clean SQLite settings use business defaults without legacy seed data', () async {
    SharedPreferences.setMockInitialValues({
      'device_id': 'clean-device-id',
      'device_name': 'CLEAN-PC',
    });
    await LocalSettingsStore.instance.initialize();
    addTearDown(SalonDatabase.instance.close);

    final repository = SqliteSettingsRepository(
      SalonDatabase.instance,
      LocalSettingsStore.instance,
    );
    final settings = await repository.fetchLocalSettings();

    expect(settings['salonName'], 'Quản Lý Salon Tóc');
    expect(settings['currency'], 'VND');
    expect(settings['appointmentReminder'], 'Bật');
    expect(settings['bankName'], isEmpty);
    expect(settings['accountNumber'], isEmpty);
    expect(settings['deviceId'], 'clean-device-id');

    final database = await SalonDatabase.instance.database;
    final businessRows = await database.query(
      'app_settings',
      where: "key LIKE 'business.%'",
    );
    expect(businessRows, isEmpty);
  });
}
