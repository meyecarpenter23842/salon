import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/appointments/presentation/pages/appointments_page.dart';
import 'package:salonmanager/features/invoices/presentation/pages/invoices_page.dart';
import 'package:salonmanager/features/overview/presentation/pages/staff_workstation_page.dart';

void main() {
  testWidgets('operations batch renders premium appointments and billing', (
    WidgetTester tester,
  ) async {
    const sizes = [
      Size(1724, 908),
      Size(1366, 768),
      Size(1024, 768),
    ];

    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in sizes) {
      tester.view.physicalSize = size;
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
                child: AppointmentsPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.byKey(const Key('appointments-premium-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('appointments-premium-workspace')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('appointments-ux-toolbar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('appointments-day-board')),
        findsOneWidget,
      );
      expect(find.text('Ngày'), findsWidgets);
      expect(find.text('Danh sách'), findsOneWidget);
      if (size.width >= 1120) {
        expect(
          find.byKey(const Key('appointments-detail-sheet')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);

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
                child: InvoicesPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.byKey(const Key('billing-premium-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('billing-premium-workspace')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('staff workstation renders premium operation workflow', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    await LocalSettingsStore.instance.initialize();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
        ],
        child: MaterialApp(
          theme: AppTheme.build(SalonThemeTemplate.salonNoirGold),
          home: const StaffWorkstationPage(standalone: true),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.byKey(const Key('staff-premium-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('staff-premium-workspace')),
      findsOneWidget,
    );
    expect(find.text('Bàn thao tác nhân viên'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
