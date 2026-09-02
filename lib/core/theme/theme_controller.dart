import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/local_settings_store.dart';
import 'salon_theme_template.dart';

final localSettingsStoreProvider = Provider<LocalSettingsStore>(
  (ref) => LocalSettingsStore.instance,
);

final salonThemeTemplateProvider =
    StateNotifierProvider<SalonThemeTemplateController, SalonThemeTemplate>(
      (ref) =>
          SalonThemeTemplateController(ref.watch(localSettingsStoreProvider)),
    );

class SalonThemeTemplateController extends StateNotifier<SalonThemeTemplate> {
  SalonThemeTemplateController(this._localSettingsStore)
    : super(_localSettingsStore.readThemeTemplate());

  final LocalSettingsStore _localSettingsStore;

  Future<void> setTemplate(SalonThemeTemplate template) async {
    if (state == template) {
      return;
    }

    state = template;
    await _localSettingsStore.saveThemeTemplate(template);
  }
}
