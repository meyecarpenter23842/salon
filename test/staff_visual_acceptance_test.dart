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
  testWidgets('Staff visual shell keeps header above list and right rail', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final appointment = AppointmentEntry(
      id: 'visual',
      customerId: 'customer-visual',
      serviceId: 'service-visual',
      employeeId: 'employee-visual',
      customerName: 'Chị Lan',
      customerPhone: '0909 123 456',
      serviceName: 'Gội đầu thư giãn',
      staffName: 'Hương',
      status: 'Đã đặt',
      durationMinutes: 90,
      slotLabel: 'Ghế 01',
      note: '',
      startsAt: DateTime(now.year, now.month, now.day, 17, 30),
      dateLabel: 'Hôm nay',
      createdAt: now,
      updatedAt: now,
    );
    final service = ServiceCatalogItem(
      id: 'service-visual',
      name: 'Hấp phục hồi',
      category: 'Chăm sóc tóc',
      durationMinutes: 60,
      price: 150000,
      description: '',
      isActive: true,
      popularityLabel: '',
      createdAt: now,
      updatedAt: now,
    );
    final product = RetailProductItem(
      id: 'product-visual',
      name: 'Serum dưỡng tóc',
      brand: 'Lumi',
      volumeLabel: '100 ml',
      productType: 'Chăm sóc tóc',
      salePrice: 280000,
      commissionPercent: 0,
      isActive: true,
      isHiddenFromStaff: false,
      createdAt: now,
      updatedAt: now,
    );
    final draft = InvoiceDraft(
      id: 'invoice-draft-001',
      appointmentId: appointment.id,
      customerId: appointment.customerId,
      discountAmount: 0,
      paymentMethod: InvoiceDraft.paymentMethods.first,
      createdAt: now,
      updatedAt: now,
      lines: const [],
    );

    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appointmentsViewProvider.overrideWith((ref) async => [appointment]),
          servicesViewProvider.overrideWith((ref) async => [service]),
          retailProductsViewProvider.overrideWith((ref) async => [product]),
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

    final header = find.byKey(const Key('staff-compact-header'));
    final filter = find.byKey(const Key('staff-filter-bar'));
    final card = find.byKey(const Key('staff-appointment-visual'));
    final rail = find.byKey(const Key('staff-quick-rail'));

    expect(header, findsOneWidget);
    expect(filter, findsOneWidget);
    expect(card, findsOneWidget);
    expect(rail, findsOneWidget);

    final headerRect = tester.getRect(header);
    final filterRect = tester.getRect(filter);
    final cardRect = tester.getRect(card);
    final railRect = tester.getRect(rail);

    expect(filterRect.top, greaterThan(headerRect.bottom));
    expect(railRect.top, greaterThan(headerRect.bottom));
    expect(railRect.left, greaterThan(cardRect.right));
    expect(cardRect.height, greaterThanOrEqualTo(100));
    expect(tester.takeException(), isNull);
  });
}
