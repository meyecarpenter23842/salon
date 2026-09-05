import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/models/appointment_entry.dart';
import 'package:salonmanager/core/models/invoice_draft.dart';
import 'package:salonmanager/core/models/retail_product_item.dart';
import 'package:salonmanager/core/models/service_catalog_item.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
import 'package:salonmanager/features/overview/presentation/pages/staff_window_workspace.dart';

void main() {
  testWidgets('standalone Staff window renders quick rail without overflow', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final appointments = [
      _appointment(
        id: 'waiting',
        startsAt: now.add(const Duration(minutes: 5)),
        status: 'Chờ xác nhận',
        customerName: 'Chị Ngọc',
      ),
      _appointment(
        id: 'unpaid',
        startsAt: now.subtract(const Duration(hours: 2)),
        status: 'Hoàn thành',
        customerName: 'Anh Huy',
      ),
    ];

    await _pumpWorkspace(
      tester,
      size: const Size(1366, 768),
      appointments: appointments,
      services: [
        _service(id: 'service-visible', name: 'Hấp phục hồi'),
        _service(id: 'service-hidden', name: 'Dịch vụ tạm ẩn', isActive: false),
      ],
      products: [
        _product(id: 'product-visible', name: 'Serum dưỡng tóc'),
        _product(
          id: 'product-hidden',
          name: 'Sản phẩm ẩn Staff',
          isHiddenFromStaff: true,
        ),
      ],
      draft: _draft(customerId: 'customer-1'),
    );

    expect(find.byKey(const Key('staff-quick-rail')), findsOneWidget);
    expect(find.byKey(const Key('staff-reminder-rail')), findsOneWidget);
    expect(find.byKey(const Key('staff-service-rail')), findsOneWidget);
    expect(find.byKey(const Key('staff-product-rail')), findsOneWidget);
    final reminderRail = find.byKey(const Key('staff-reminder-rail'));
    expect(
      find.descendant(of: reminderRail, matching: find.text('Chị Ngọc')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: reminderRail, matching: find.text('Anh Huy')),
      findsOneWidget,
    );
    expect(find.text('Hấp phục hồi'), findsOneWidget);
    expect(find.text('Serum dưỡng tóc'), findsOneWidget);
    expect(find.text('Dịch vụ tạm ẩn'), findsNothing);
    expect(find.text('Sản phẩm ẩn Staff'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('service picker searches long active catalog', (
    WidgetTester tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(1600, 900),
      appointments: const [],
      services: [
        _service(id: 'service-1', name: 'Hấp phục hồi'),
        _service(
          id: 'service-2',
          name: 'Massage vai gáy',
          category: 'Thư giãn',
        ),
        _service(id: 'service-3', name: 'Ủ tóc collagen'),
      ],
      products: const [],
      draft: _draft(customerId: 'customer-1'),
    );

    await tester.tap(find.byKey(const Key('staff-rail-services-more')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('staff-service-picker-search')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('staff-service-picker-search')),
      'massage',
    );
    await tester.pump();

    expect(find.text('Massage vai gáy'), findsOneWidget);
    expect(find.text('Hấp phục hồi'), findsNothing);
    expect(find.text('Ủ tóc collagen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product picker searches name type and brand', (
    WidgetTester tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(1600, 900),
      appointments: const [],
      services: const [],
      products: [
        _product(
          id: 'product-1',
          name: 'Serum dưỡng tóc',
          brand: 'Lumi',
        ),
        _product(
          id: 'product-2',
          name: 'Dầu gội phục hồi',
          brand: 'Herbal Lab',
          productType: 'Dầu gội',
        ),
      ],
      draft: _draft(customerId: 'customer-1'),
    );

    await tester.tap(find.byKey(const Key('staff-rail-products-more')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('staff-product-picker-search')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('staff-product-picker-search')),
      'herbal',
    );
    await tester.pump();

    expect(find.text('Dầu gội phục hồi'), findsOneWidget);
    expect(find.text('Serum dưỡng tóc'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace refreshes providers after returning from Staff POS route', (
    WidgetTester tester,
  ) async {
    var appointmentReads = 0;
    await _pumpWorkspace(
      tester,
      size: const Size(1366, 768),
      appointments: const [],
      services: const [],
      products: const [],
      draft: _draft(),
      onAppointmentsRead: () => appointmentReads += 1,
    );

    final beforeNavigation = appointmentReads;
    final workspaceContext = tester.element(find.byType(StaffWindowWorkspace));
    final routeFuture = Navigator.of(workspaceContext).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Staff POS route')),
      ),
    );
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.text('Staff POS route'))).pop();
    await routeFuture;
    await tester.pumpAndSettle();

    expect(appointmentReads, greaterThan(beforeNavigation));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact Staff window keeps quick rail behind one action', (
    WidgetTester tester,
  ) async {
    await _pumpWorkspace(
      tester,
      size: const Size(1100, 768),
      appointments: const [],
      services: const [],
      products: const [],
      draft: _draft(),
    );

    expect(find.byKey(const Key('staff-quick-rail')), findsNothing);
    expect(find.byKey(const Key('staff-quick-rail-open')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required Size size,
  required List<AppointmentEntry> appointments,
  required List<ServiceCatalogItem> services,
  required List<RetailProductItem> products,
  required InvoiceDraft draft,
  VoidCallback? onAppointmentsRead,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appointmentsViewProvider.overrideWith((ref) async {
          onAppointmentsRead?.call();
          return appointments;
        }),
        servicesViewProvider.overrideWith((ref) async => services),
        retailProductsViewProvider.overrideWith((ref) async => products),
        invoiceDraftProvider.overrideWith((ref) async => draft),
      ],
      child: MaterialApp(
        navigatorObservers: [staffWindowRouteObserver],
        home: const StaffWindowWorkspace(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle(const Duration(milliseconds: 120));
}

AppointmentEntry _appointment({
  required String id,
  required DateTime startsAt,
  required String status,
  required String customerName,
}) {
  final now = DateTime.now();
  return AppointmentEntry(
    id: id,
    customerId: 'customer-$id',
    serviceId: 'service-1',
    employeeId: 'employee-1',
    customerName: customerName,
    customerPhone: '0900000000',
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
  );
}

ServiceCatalogItem _service({
  required String id,
  required String name,
  String category = 'Chăm sóc tóc',
  bool isActive = true,
}) {
  final now = DateTime.now();
  return ServiceCatalogItem(
    id: id,
    name: name,
    category: category,
    durationMinutes: 60,
    price: 150000,
    description: '',
    isActive: isActive,
    popularityLabel: '',
    createdAt: now,
    updatedAt: now,
  );
}

RetailProductItem _product({
  required String id,
  required String name,
  String brand = '',
  String productType = 'Chăm sóc tóc',
  bool isActive = true,
  bool isHiddenFromStaff = false,
}) {
  final now = DateTime.now();
  return RetailProductItem(
    id: id,
    name: name,
    brand: brand,
    volumeLabel: '100 ml',
    productType: productType,
    salePrice: 250000,
    commissionPercent: 0,
    isActive: isActive,
    isHiddenFromStaff: isHiddenFromStaff,
    createdAt: now,
    updatedAt: now,
  );
}

InvoiceDraft _draft({String customerId = ''}) {
  final now = DateTime.now();
  return InvoiceDraft(
    id: 'invoice-draft-001',
    appointmentId: null,
    customerId: customerId,
    discountAmount: 0,
    paymentMethod: InvoiceDraft.paymentMethods.first,
    createdAt: now,
    updatedAt: now,
    lines: const [],
  );
}
