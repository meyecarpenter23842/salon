import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/overview/presentation/pages/overview_page.dart';

void main() {
  testWidgets('today operations dashboard stays viewport-fixed on desktop', (
    WidgetTester tester,
  ) async {
    const sizes = [Size(1366, 768), Size(1024, 768)];

    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      SharedPreferences.setMockInitialValues({});
      await LocalSettingsStore.instance.initialize();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
          ],
          child: MaterialApp(
            theme: AppTheme.build(SalonThemeTemplate.salonNoirGold),
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: OverviewPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      final workspace = find.byKey(const Key('overview-premium-workspace'));
      expect(workspace, findsOneWidget);
      expect(tester.widget(workspace), isA<Column>());
      expect(find.byKey(const Key('overview-premium-header')), findsOneWidget);
      expect(find.byKey(const Key('overview-today-flow')), findsOneWidget);
      expect(find.byKey(const Key('overview-team-status')), findsOneWidget);
      expect(find.byKey(const Key('overview-operational-alerts')), findsOneWidget);
      expect(find.byKey(const Key('overview-top-sales')), findsOneWidget);
      expect(find.byKey(const Key('overview-open-appointments')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '${size.width}x${size.height}');
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
