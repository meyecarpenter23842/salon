import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/reports/presentation/pages/reports_page.dart';
import 'package:salonmanager/features/settings/presentation/pages/settings_page.dart';

void main() {
  testWidgets('final polish renders reports and settings at desktop sizes', (
    WidgetTester tester,
  ) async {
    const sizes = [
      Size(1724, 908),
      Size(1366, 768),
      Size(1280, 720),
      Size(1024, 768),
    ];

    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      await _pumpPage(tester, const ReportsPage());
      expect(find.byKey(const Key('reports-premium-header')), findsOneWidget);
      expect(find.byKey(const Key('reports-premium-workspace')), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: '${size.width}x${size.height} / reports',
      );

      await _pumpPage(tester, const SettingsPage());
      expect(find.byKey(const Key('settings-premium-header')), findsOneWidget);
      expect(find.byKey(const Key('settings-premium-workspace')), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: '${size.width}x${size.height} / settings',
      );
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('final polish renders reports and settings across four themes', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final theme in SalonThemeTemplate.values) {
      await _pumpPage(tester, const ReportsPage(), theme: theme);
      expect(find.byKey(const Key('reports-premium-header')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '${theme.name} / reports');

      await _pumpPage(tester, const SettingsPage(), theme: theme);
      expect(find.byKey(const Key('settings-premium-header')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '${theme.name} / settings');
    }
  });

  testWidgets('settings theme chooser exposes four approved options', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpPage(tester, const SettingsPage());

    final workspace = find.byKey(const Key('settings-premium-workspace'));
    expect(workspace, findsOneWidget);

    final themeHub = find.byKey(const Key('settings-hub-theme'));
    if (themeHub.evaluate().isEmpty) {
      await tester.drag(workspace, const Offset(0, -320));
      await tester.pumpAndSettle(const Duration(milliseconds: 120));
    }
    expect(themeHub, findsOneWidget);
    await tester.ensureVisible(themeHub);
    await tester.tap(themeHub);
    await tester.pumpAndSettle(const Duration(milliseconds: 120));

    for (final template in SalonThemeTemplate.values) {
      expect(find.byKey(Key('settings-theme-${template.name}')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page, {
  SalonThemeTemplate theme = SalonThemeTemplate.salonNoirGold,
}) async {
  SharedPreferences.setMockInitialValues({});
  await LocalSettingsStore.instance.initialize();
  await LocalSettingsStore.instance.saveThemeTemplate(theme);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDataBackendProvider.overrideWithValue(AppDataBackend.fake)],
      child: MaterialApp(
        theme: AppTheme.build(theme),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: page,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 180));
  await tester.pumpAndSettle(const Duration(milliseconds: 120));
}
