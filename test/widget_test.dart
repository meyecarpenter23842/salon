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
    'renders desktop workflows and keeps shell interactions usable',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1724, 908);
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
      expect(find.text('VẬN HÀNH'), findsOneWidget);
      expect(find.text('QUẢN LÝ'), findsOneWidget);
      expect(find.text('THEO DÕI'), findsOneWidget);
      expect(find.byTooltip('Thu gọn menu'), findsOneWidget);
      expect(find.text('SQLite runtime'), findsNothing);
      expect(find.text('Tính tiền nhanh'), findsNothing);
      expect(tester.takeException(), isNull);

      // Exercise real hit testing instead of mutating the navigation provider.
      await tester.tap(find.text('Lịch hẹn').first);
      await pumpUi(tester);
      expect(container.read(desktopSectionProvider), DesktopSection.appointments);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Tổng quan').first);
      await pumpUi(tester);
      expect(container.read(desktopSectionProvider), DesktopSection.overview);

      // Overview actions must be real navigation controls, not disabled mock UI.
      await tester.tap(find.byKey(const Key('overview-open-appointments')));
      await pumpUi(tester);
      expect(container.read(desktopSectionProvider), DesktopSection.appointments);
      expect(tester.takeException(), isNull);

      container.read(desktopSectionProvider.notifier).state =
          DesktopSection.overview;
      await pumpUi(tester);

      await tester.tap(find.byTooltip('Thu gọn menu'));
      await pumpUi(tester);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('salon_sidebar_collapsed'), isTrue);
      expect(find.byTooltip('Mở rộng menu'), findsOneWidget);

      await tester.tap(find.byTooltip('Mở rộng menu'));
      await pumpUi(tester);
      expect(preferences.getBool('salon_sidebar_collapsed'), isFalse);

      for (final section in DesktopSection.values) {
        container.read(desktopSectionProvider.notifier).state = section;
        await pumpUi(tester);
        expect(container.read(desktopSectionProvider), section);
        expect(tester.takeException(), isNull);
      }

      container.read(desktopSectionProvider.notifier).state =
          DesktopSection.employees;
      await pumpUi(tester);
      expect(container.read(desktopSectionProvider), DesktopSection.employees);
      expect(find.text('Nhân viên'), findsWidgets);

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
