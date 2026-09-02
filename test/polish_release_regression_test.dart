import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/app/app.dart';
import 'package:salonmanager/app/navigation/desktop_navigation.dart';
import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/features/appointments/presentation/pages/appointments_page.dart';
import 'package:salonmanager/features/customers/presentation/pages/customers_page.dart';
import 'package:salonmanager/features/employees/presentation/pages/employees_page.dart';
import 'package:salonmanager/features/invoices/presentation/pages/invoices_page.dart';
import 'package:salonmanager/features/overview/presentation/pages/overview_page.dart';
import 'package:salonmanager/features/reports/presentation/pages/reports_page.dart';
import 'package:salonmanager/features/sales/presentation/pages/sales_page.dart';
import 'package:salonmanager/features/services/presentation/pages/services_page.dart';
import 'package:salonmanager/features/settings/presentation/pages/settings_page.dart';

void main() {
  final workspaceTypes = <DesktopSection, Type>{
    DesktopSection.overview: OverviewPage,
    DesktopSection.appointments: AppointmentsPage,
    DesktopSection.invoices: InvoicesPage,
    DesktopSection.customers: CustomersPage,
    DesktopSection.services: ServicesPage,
    DesktopSection.sales: SalesPage,
    DesktopSection.employees: EmployeesPage,
    DesktopSection.reports: ReportsPage,
    DesktopSection.settings: SettingsPage,
  };

  test('approved main navigation remains one-to-one with desktop sections', () {
    expect(desktopNavigationItems.length, DesktopSection.values.length);
    expect(
      desktopNavigationItems.map((item) => item.section).toSet(),
      DesktopSection.values.toSet(),
    );
    expect(workspaceTypes.keys.toSet(), DesktopSection.values.toSet());
  });

  testWidgets(
    'release regression renders every main workspace across desktop sizes',
    (WidgetTester tester) async {
      const sizes = [
        Size(1366, 768),
        Size(1280, 720),
        Size(1024, 768),
      ];

      SharedPreferences.setMockInitialValues({});
      await LocalSettingsStore.instance.initialize();

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final size in sizes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
            ],
            child: const SalonManagerApp(),
          ),
        );
        await _pumpUi(tester);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SalonManagerApp)),
        );

        for (final section in DesktopSection.values) {
          container.read(desktopSectionProvider.notifier).state = section;
          await _pumpUi(tester);

          expect(container.read(desktopSectionProvider), section);
          expect(
            find.byType(workspaceTypes[section]!),
            findsOneWidget,
            reason: '${size.width}x${size.height} / ${section.name} routed page',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${size.width}x${size.height} / ${section.name}',
          );
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 320));
}
