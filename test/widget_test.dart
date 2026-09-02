import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/app/app.dart';
import 'package:salonmanager/app/navigation/desktop_navigation.dart';
import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';

void main() {
  testWidgets(
    'renders desktop workflows and persists theme selection locally',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      await LocalSettingsStore.instance.initialize();
      expect(
        LocalSettingsStore.instance.readThemeTemplate(),
        SalonThemeTemplate.salonNoirGold,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
          ],
          child: const SalonManagerApp(),
        ),
      );
      await pumpUi(tester);

      final container = containerOf(tester);
      expect(find.byType(SalonManagerApp), findsOneWidget);

      for (final section in const [
        DesktopSection.overview,
        DesktopSection.customers,
        DesktopSection.appointments,
        DesktopSection.services,
        DesktopSection.employees,
        DesktopSection.invoices,
        DesktopSection.reports,
        DesktopSection.settings,
      ]) {
        container.read(desktopSectionProvider.notifier).state = section;
        await pumpUi(tester);
        expect(container.read(desktopSectionProvider), section);
        expect(tester.takeException(), isNull);
      }

      await LocalSettingsStore.instance.saveThemeTemplate(
        SalonThemeTemplate.salonSapphire,
      );
      expect(
        LocalSettingsStore.instance.readThemeTemplate(),
        SalonThemeTemplate.salonSapphire,
      );

      await LocalSettingsStore.instance.saveThemeTemplate(
        SalonThemeTemplate.salonEmerald,
      );
      expect(
        LocalSettingsStore.instance.readThemeTemplate(),
        SalonThemeTemplate.salonEmerald,
      );

      await LocalSettingsStore.instance.saveThemeTemplate(
        SalonThemeTemplate.salonNoirGold,
      );
      expect(
        LocalSettingsStore.instance.readThemeTemplate(),
        SalonThemeTemplate.salonNoirGold,
      );
    },
  );
}

Future<void> pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

ProviderContainer containerOf(WidgetTester tester) {
  final context = tester.element(find.byType(SalonManagerApp));
  return ProviderScope.containerOf(context);
}
