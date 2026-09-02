import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/repositories/sqlite_settings_repository.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';

void main() {
  test('restored SQLite business settings win over stale local preferences', () async {
    SharedPreferences.setMockInitialValues({
      'salon_name': 'Stale Local Salon',
      'payment_bank_name': 'Stale Local Bank',
      'device_id': 'same-machine-id',
    });
    await LocalSettingsStore.instance.initialize();
    addTearDown(SalonDatabase.instance.close);

    final database = await SalonDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    await database.insert('app_settings', {
      'key': 'business.salon_name',
      'value': 'Restored Salon',
      'updated_at': now,
    });
    await database.insert('app_settings', {
      'key': 'business.payment.bank_name',
      'value': 'Restored Bank',
      'updated_at': now,
    });

    final repository = SqliteSettingsRepository(
      SalonDatabase.instance,
      LocalSettingsStore.instance,
    );
    final settings = await repository.fetchLocalSettings();

    expect(settings['salonName'], 'Restored Salon');
    expect(settings['bankName'], 'Restored Bank');
    expect(settings['deviceId'], 'same-machine-id');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('salon_name'), isFalse);
    expect(preferences.containsKey('payment_bank_name'), isFalse);
    expect(preferences.getString('device_id'), 'same-machine-id');
  });
}
