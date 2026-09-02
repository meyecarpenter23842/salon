import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
import 'package:salonmanager/core/repositories/fake_repositories.dart';
import 'package:salonmanager/core/repositories/sqlite_settings_repository.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';

void main() {
  test('settings repository follows the selected data backend', () async {
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsStore.instance.initialize();

    final sqliteContainer = ProviderContainer();
    addTearDown(sqliteContainer.dispose);
    expect(
      sqliteContainer.read(settingsRepositoryProvider),
      isA<SqliteSettingsRepository>(),
    );

    final fakeContainer = ProviderContainer(
      overrides: [
        appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
      ],
    );
    addTearDown(fakeContainer.dispose);
    expect(
      fakeContainer.read(settingsRepositoryProvider),
      isA<FakeSettingsRepository>(),
    );
  });
}
