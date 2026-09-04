import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/app/navigation/desktop_navigation.dart';
import 'package:salonmanager/app/navigation/flow_navigation.dart';
import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/appointments/presentation/pages/appointments_page.dart';
import 'package:salonmanager/features/customers/presentation/pages/customers_page.dart';
import 'package:salonmanager/features/employees/presentation/pages/employees_page.dart';
import 'package:salonmanager/features/services/presentation/pages/services_page.dart';

void main() {
  test('employee deeplink keeps target id when names overlap', () {
    final employees = <Map<String, Object?>>[
      {
        'id': 'emp-001',
        'name': 'An',
        'role': 'Stylist chính',
        'specialty': 'Color',
        'phone': '0901000001',
        'status': 'Đang làm việc',
      },
      {
        'id': 'emp-002',
        'name': 'An',
        'role': 'Barber',
        'specialty': 'Cắt nam',
        'phone': '0901000002',
        'status': 'Đang làm việc',
      },
      {
        'id': 'emp-003',
        'name': 'An Nguyễn',
        'role': 'Chăm sóc tóc',
        'specialty': 'Phục hồi',
        'phone': '0901000003',
        'status': 'Sắp có lịch',
      },
    ];

    expect(
      employeeSearchResultIndexForId(
        employees,
        employeeId: 'emp-002',
        query: 'An',
      ),
      1,
    );
    expect(
      employeeSearchResultIndexForId(
        employees,
        employeeId: 'emp-003',
        query: 'An',
      ),
      2,
    );
  });

  testWidgets('appointment detail links keep the selected entity context', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        appDataBackendProvider.overrideWithValue(AppDataBackend.fake),
      ],
    );
    addTearDown(container.dispose);

    final customers =
        await container.read(customersRepositoryProvider).fetchCustomersView();
    final customerIds = customers.map((item) => item.id).toSet();
    final appointments = await container.read(filteredAppointmentsProvider.future);
    final targetIndex = appointments.indexWhere(
      (item) =>
          customerIds.contains(item.customerId) &&
          item.employeeId != null &&
          item.serviceId != null &&
          item.status != 'Chờ xác nhận' &&
          item.status != 'Đã hủy',
    );
    expect(targetIndex, greaterThanOrEqualTo(0));
    final appointment = appointments[targetIndex];
    final employees =
        await container.read(employeesRepositoryProvider).fetchEmployeesView();
    final expectedEmployeeIndex = employeeSearchResultIndexForId(
      employees,
      employeeId: appointment.employeeId!,
      query: appointment.staffName,
    );
    expect(expectedEmployeeIndex, greaterThanOrEqualTo(0));
    container.read(selectedAppointmentIndexProvider.notifier).state = targetIndex;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.build(SalonThemeTemplate.salonNoirGold),
          home: const Scaffold(body: AppointmentsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('appointments-detail-sheet')), findsOneWidget);
    expect(find.byKey(const Key('appointment-open-customer')), findsOneWidget);
    expect(find.byKey(const Key('appointment-open-employee')), findsOneWidget);
    expect(find.byKey(const Key('appointment-open-service')), findsOneWidget);
    expect(find.byKey(const Key('appointment-open-checkout')), findsOneWidget);

    await tester.tap(find.byKey(const Key('appointment-open-customer')));
    await tester.pump();
    expect(container.read(desktopSectionProvider), DesktopSection.customers);
    expect(
      container.read(customerProfileDetailIdProvider),
      appointment.customerId,
    );

    await tester.tap(find.byKey(const Key('appointment-open-employee')));
    await tester.pumpAndSettle();
    expect(container.read(desktopSectionProvider), DesktopSection.employees);
    expect(container.read(employeeRoleFilterProvider), 'Tất cả');
    expect(container.read(employeeSearchQueryProvider), appointment.staffName);
    expect(
      container.read(selectedEmployeeIndexProvider),
      expectedEmployeeIndex,
    );

    await tester.tap(find.byKey(const Key('appointment-open-service')));
    await tester.pumpAndSettle();
    expect(container.read(desktopSectionProvider), DesktopSection.services);
    expect(container.read(serviceSearchQueryProvider), appointment.serviceName);

    final checkoutFinder = find.byKey(const Key('appointment-open-checkout'));
    await tester.ensureVisible(checkoutFinder);
    await tester.pumpAndSettle();
    await tester.tap(checkoutFinder);
    await tester.pumpAndSettle();
    expect(container.read(desktopSectionProvider), DesktopSection.invoices);
    final draft = await container.read(invoiceDraftProvider.future);
    expect(draft.appointmentId, appointment.id);
    expect(draft.customerId, appointment.customerId);
    expect(draft.lines, isNotEmpty);
  });
}
