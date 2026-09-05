import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/app/app.dart';
import 'package:salonmanager/app/navigation/desktop_navigation.dart';
import 'package:salonmanager/core/models/appointment_entry.dart';
import 'package:salonmanager/core/models/invoice_draft.dart';
import 'package:salonmanager/core/models/invoice_draft_line.dart';
import 'package:salonmanager/core/models/retail_product_item.dart';
import 'package:salonmanager/core/models/service_catalog_item.dart';
import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/features/overview/presentation/pages/staff_workstation_page.dart';

void main() {
  testWidgets('staff workstation opens current global bill from header', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
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
        child: const SalonManagerApp(),
      ),
    );

    await pumpUi(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SalonManagerApp)),
      listen: false,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Bàn nhân viên'));
    await pumpUi(tester);

    expect(find.text('Bàn thao tác nhân viên'), findsOneWidget);
    expect(find.textContaining('Bill:'), findsOneWidget);

    await tester.tap(find.byKey(const Key('staff-open-billing')));
    await pumpUi(tester);

    expect(container.read(desktopSectionProvider), DesktopSection.invoices);
    expect(find.byKey(const Key('billing-premium-workspace')), findsOneWidget);
  });

  testWidgets('staff workstation never falls back to another day', (
    WidgetTester tester,
  ) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final appointment = _appointment(
      id: 'tomorrow-only',
      startsAt: DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        9,
      ),
      status: 'Đã đặt',
      customerName: 'Khách ngày mai',
    );

    await _pumpStandalone(
      tester,
      appointments: [appointment],
      draft: _draft(),
    );

    expect(find.text('Hôm nay chưa có lịch'), findsOneWidget);
    expect(find.text('Khách ngày mai'), findsNothing);
  });

  testWidgets('completed unpaid and paid appointments derive correct state', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final unpaid = _appointment(
      id: 'unpaid',
      startsAt: DateTime(now.year, now.month, now.day, 10),
      status: 'Hoàn thành',
      customerName: 'Khách chờ thu',
    );
    final paid = _appointment(
      id: 'paid',
      startsAt: DateTime(now.year, now.month, now.day, 11),
      status: 'Hoàn thành',
      customerName: 'Khách đã thu',
      isPaid: true,
    );

    await _pumpStandalone(
      tester,
      appointments: [unpaid, paid],
      draft: _draft(),
    );

    final unpaidCard = find.byKey(const Key('staff-appointment-unpaid'));
    final paidCard = find.byKey(const Key('staff-appointment-paid'));

    expect(
      find.descendant(of: unpaidCard, matching: find.text('Chờ thu')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: paidCard, matching: find.text('Đã thu')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: paidCard,
        matching: find.text('Hoàn tác hoàn thành'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: paidCard, matching: find.text('Tính tiền')),
      findsNothing,
    );
    expect(find.byKey(const Key('staff-actions-paid')), findsNothing);
  });

  testWidgets('staff wording matches existing appointment and bill semantics', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final waiting = _appointment(
      id: 'waiting',
      startsAt: DateTime(now.year, now.month, now.day, 9),
      status: 'Chờ xác nhận',
      customerName: 'Khách chờ xác nhận',
    );

    await _pumpStandalone(
      tester,
      appointments: [waiting],
      draft: _draft(),
    );

    expect(find.text('Xác nhận lịch'), findsOneWidget);
    expect(find.text('Nhận khách'), findsNothing);

    await tester.tap(find.byKey(const Key('staff-actions-waiting')));
    await tester.pumpAndSettle();

    expect(find.text('Thêm phát sinh vào bill'), findsOneWidget);
  });

  testWidgets('staff header resolves appointment-linked global draft', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final appointment = _appointment(
      id: 'apt-current',
      startsAt: DateTime(now.year, now.month, now.day, 14),
      status: 'Đang làm',
      customerName: 'Chị Lan',
      customerId: 'customer-lan',
    );
    final draft = _draft(
      appointmentId: appointment.id,
      customerId: appointment.customerId,
      lines: [_line()],
    );

    await _pumpStandalone(
      tester,
      appointments: [appointment],
      draft: draft,
    );

    expect(find.textContaining('Bill: Chị Lan'), findsOneWidget);
    expect(find.text('Mở bill'), findsOneWidget);
  });

  testWidgets('staff blocks checkout when another global draft has data', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
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
        child: const SalonManagerApp(),
      ),
    );
    await pumpUi(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SalonManagerApp)),
      listen: false,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Bàn nhân viên'));
    await pumpUi(tester);

    await tester.tap(find.byKey(const Key('staff-checkout-apt-003')));
    await tester.pumpAndSettle();

    expect(find.text('Đang có bill chưa hoàn tất'), findsOneWidget);
    expect(container.read(desktopSectionProvider), isNot(DesktopSection.invoices));
  });

  testWidgets('staff workstation uses compact operation-first desktop layout', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final appointments = [
      _appointment(
        id: 'layout-booked',
        startsAt: DateTime(now.year, now.month, now.day, 9),
        status: 'Đã đặt',
        customerName: 'Khách layout',
      ),
      _appointment(
        id: 'layout-active',
        startsAt: DateTime(now.year, now.month, now.day, 10),
        status: 'Đang làm',
        customerName: 'Khách đang làm',
      ),
    ];

    await _pumpStandalone(
      tester,
      appointments: appointments,
      draft: _draft(),
      size: const Size(1366, 768),
    );

    expect(find.byKey(const Key('staff-compact-header')), findsOneWidget);
    expect(find.byKey(const Key('staff-search')), findsOneWidget);
    expect(find.byKey(const Key('staff-filter-bar')), findsOneWidget);
    expect(find.byKey(const Key('staff-operation-workspace')), findsOneWidget);
    expect(find.text('Lượt hôm nay'), findsNothing);
    expect(find.text('Đang phục vụ'), findsNothing);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1600, 900);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff search matches customer name and phone', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final lan = _appointment(
      id: 'search-lan',
      startsAt: DateTime(now.year, now.month, now.day, 9),
      status: 'Đã đặt',
      customerName: 'Chị Lan',
      customerPhone: '0909 123 456',
    );
    final minh = _appointment(
      id: 'search-minh',
      startsAt: DateTime(now.year, now.month, now.day, 10),
      status: 'Đang làm',
      customerName: 'Anh Minh',
      customerPhone: '0938 111 444',
    );

    await _pumpStandalone(
      tester,
      appointments: [lan, minh],
      draft: _draft(),
    );

    await tester.enterText(find.byKey(const Key('staff-search')), '0938');
    await tester.pump();

    expect(find.text('Anh Minh'), findsOneWidget);
    expect(find.text('Chị Lan'), findsNothing);

    await tester.enterText(find.byKey(const Key('staff-search')), 'lan');
    await tester.pump();

    expect(find.text('Chị Lan'), findsOneWidget);
    expect(find.text('Anh Minh'), findsNothing);
  });

  testWidgets('staff filters states and exposes one primary action per row', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final waiting = _appointment(
      id: 'primary-waiting',
      startsAt: DateTime(now.year, now.month, now.day, 9),
      status: 'Chờ xác nhận',
      customerName: 'Khách chờ',
    );
    final booked = _appointment(
      id: 'primary-booked',
      startsAt: DateTime(now.year, now.month, now.day, 10),
      status: 'Đã đặt',
      customerName: 'Khách đã đặt',
    );
    final active = _appointment(
      id: 'primary-active',
      startsAt: DateTime(now.year, now.month, now.day, 11),
      status: 'Đang làm',
      customerName: 'Khách đang làm',
    );
    final unpaid = _appointment(
      id: 'primary-unpaid',
      startsAt: DateTime(now.year, now.month, now.day, 12),
      status: 'Hoàn thành',
      customerName: 'Khách chờ thu',
    );

    await _pumpStandalone(
      tester,
      appointments: [waiting, booked, active, unpaid],
      draft: _draft(),
    );

    final waitingCard =
        find.byKey(const Key('staff-appointment-primary-waiting'));
    final bookedCard = find.byKey(const Key('staff-appointment-primary-booked'));
    final activeCard = find.byKey(const Key('staff-appointment-primary-active'));
    final unpaidCard = find.byKey(const Key('staff-appointment-primary-unpaid'));

    expect(
      find.descendant(of: waitingCard, matching: find.text('Xác nhận lịch')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: waitingCard, matching: find.text('Bắt đầu')),
      findsNothing,
    );
    expect(
      find.descendant(of: bookedCard, matching: find.text('Bắt đầu')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bookedCard, matching: find.text('Tính tiền')),
      findsNothing,
    );
    expect(
      find.descendant(of: activeCard, matching: find.text('Hoàn thành')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: activeCard, matching: find.text('Tính tiền')),
      findsNothing,
    );
    expect(
      find.descendant(of: unpaidCard, matching: find.text('Tính tiền')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('staff-filter-active')));
    await tester.pump();

    expect(find.text('Khách đang làm'), findsOneWidget);
    expect(find.text('Khách chờ'), findsNothing);
    expect(find.text('Khách đã đặt'), findsNothing);
    expect(find.text('Khách chờ thu'), findsNothing);
  });
}

Future<void> _pumpStandalone(
  WidgetTester tester, {
  required List<AppointmentEntry> appointments,
  required InvoiceDraft draft,
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appointmentsViewProvider.overrideWith((ref) async => appointments),
        servicesViewProvider.overrideWith(
          (ref) async => <ServiceCatalogItem>[],
        ),
        retailProductsViewProvider.overrideWith(
          (ref) async => <RetailProductItem>[],
        ),
        invoiceDraftProvider.overrideWith((ref) async => draft),
      ],
      child: const MaterialApp(home: StaffWorkstationPage(standalone: true)),
    ),
  );
  await pumpUi(tester);
}

AppointmentEntry _appointment({
  required String id,
  required DateTime startsAt,
  required String status,
  required String customerName,
  String customerId = 'customer-1',
  String customerPhone = '0900000000',
  bool isPaid = false,
}) {
  final now = DateTime.now();
  return AppointmentEntry(
    id: id,
    customerId: customerId,
    serviceId: 'service-1',
    employeeId: 'employee-1',
    customerName: customerName,
    customerPhone: customerPhone,
    serviceName: 'Gội đầu',
    staffName: 'Hương',
    status: status,
    durationMinutes: 60,
    slotLabel: 'Ghế 01',
    note: '',
    startsAt: startsAt,
    dateLabel: 'Hôm nay',
    createdAt: now,
    updatedAt: now,
    isPaid: isPaid,
  );
}

InvoiceDraft _draft({
  String? appointmentId,
  String customerId = '',
  List<InvoiceDraftLine> lines = const [],
}) {
  final now = DateTime.now();
  return InvoiceDraft(
    id: 'invoice-draft-001',
    appointmentId: appointmentId,
    customerId: customerId,
    discountAmount: 0,
    paymentMethod: InvoiceDraft.paymentMethods.first,
    createdAt: now,
    updatedAt: now,
    lines: lines,
  );
}

InvoiceDraftLine _line() {
  return InvoiceDraftLine(
    id: 'line-1',
    invoiceId: 'invoice-draft-001',
    itemType: 'service',
    serviceId: 'service-1',
    productId: null,
    employeeId: 'employee-1',
    title: 'Gội đầu',
    quantity: 1,
    unitPrice: 100000,
    discountAmount: 0,
    totalPrice: 100000,
  );
}

Future<void> pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pumpAndSettle(const Duration(milliseconds: 120));
}
