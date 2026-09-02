import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/customers/presentation/pages/customers_page.dart';
import 'package:salonmanager/features/employees/presentation/pages/employees_page.dart';
import 'package:salonmanager/features/sales/presentation/pages/sales_page.dart';
import 'package:salonmanager/features/services/presentation/pages/services_page.dart';

void main() {
  testWidgets('management batch renders premium workspaces at desktop sizes', (tester) async {
    const sizes = [Size(1724, 908), Size(1366, 768), Size(1024, 768)];

    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      await _pumpPage(tester, const CustomersPage());
      expect(find.byKey(const Key('customers-premium-header')), findsOneWidget);
      expect(find.byKey(const Key('customers-premium-workspace')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _pumpPage(tester, const ServicesPage());
      expect(find.byKey(const Key('services-premium-header')), findsOneWidget);
      expect(find.byKey(const Key('services-premium-workspace')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _pumpPage(tester, const SalesPage());
      expect(find.byKey(const Key('sales-premium-header')), findsOneWidget);
      expect(find.byKey(const Key('sales-premium-workspace')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _pumpPage(tester, const EmployeesPage());
      expect(find.byKey(const Key('employees-premium-header')), findsOneWidget);
      expect(find.byKey(const Key('employees-premium-workspace')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('management batch renders across four approved themes', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final theme in SalonThemeTemplate.values) {
      await _pumpPage(tester, const CustomersPage(), theme: theme);
      expect(find.byKey(const Key('customers-premium-header')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page, {
  SalonThemeTemplate theme = SalonThemeTemplate.salonNoirGold,
}) async {
  SharedPreferences.setMockInitialValues({});
  await LocalSettingsStore.instance.initialize();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDataBackendProvider.overrideWithValue(AppDataBackend.fake)],
      child: MaterialApp(theme: AppTheme.build(theme), home: Scaffold(body: Padding(padding: const EdgeInsets.all(18), child: page))),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pumpAndSettle(const Duration(milliseconds: 120));
}
