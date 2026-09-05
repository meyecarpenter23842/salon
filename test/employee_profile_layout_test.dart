import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/employees/presentation/pages/employees_page.dart';

void main() {
  testWidgets('employee V2 profile stays viewport-fixed on desktop sizes', (
    WidgetTester tester,
  ) async {
    const sizes = [Size(1366, 768), Size(1024, 768)];

    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

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
                child: EmployeesPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle(const Duration(milliseconds: 120));

      expect(
        find.byKey(const Key('employees-premium-workspace')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('employees-premium-header')), findsOneWidget);
      expect(find.byKey(const Key('employee-profile-card')), findsOneWidget);
      expect(
        find.byKey(const Key('employee-profile-edit-action')),
        findsOneWidget,
      );
      expect(
        tester.takeException(),
        isNull,
        reason: '${size.width}x${size.height}',
      );
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('employee editor no longer asks for derived monthly metrics', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
        ],
        child: MaterialApp(
          theme: AppTheme.build(SalonThemeTemplate.salonNoirGold),
          home: const Scaffold(
            body: Padding(padding: EdgeInsets.all(16), child: EmployeesPage()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('employee-profile-edit-action')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Họ tên'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'Hoa hồng / KPI'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Dịch vụ tháng'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Doanh thu tháng'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Lịch hôm nay'), findsNothing);
    expect(
      find.textContaining('được hệ thống tự tính từ dữ liệu thật'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
