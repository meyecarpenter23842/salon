import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/appointment_entry.dart';
import 'package:salonmanager/core/models/invoice_draft.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
import 'package:salonmanager/core/repositories/sqlite_billing_sessions_repository.dart';
import 'package:salonmanager/core/settings/local_settings_store.dart';
import 'package:salonmanager/core/theme/app_theme.dart';
import 'package:salonmanager/core/theme/salon_theme_template.dart';
import 'package:salonmanager/features/invoices/presentation/pages/invoices_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
    SharedPreferences.setMockInitialValues({});
    await LocalSettingsStore.instance.initialize();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('selected repositories keep their target and guard double checkout', () async {
    final fixture = await _createFixture(3);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sessions = container.read(billingSessionsRepositoryProvider);
    final drafts = <InvoiceDraft>[];
    for (final appointment in fixture.appointments) {
      drafts.add(await sessions.openAppointmentSession(appointment));
    }

    container.read(selectedInvoiceSessionIdProvider.notifier).state = drafts[0].id;
    final targetA = container.read(invoicesRepositoryProvider);
    container.read(selectedInvoiceSessionIdProvider.notifier).state = drafts[1].id;
    final targetB = container.read(invoicesRepositoryProvider);
    await targetA.addInvoiceService(fixture.serviceId, employeeId: fixture.employeeId);
    expect((await targetA.fetchInvoiceDraft()).lines.single.quantity, 2);
    expect((await targetB.fetchInvoiceDraft()).lines.single.quantity, 1);
    expect((await sessions.fetchSession(drafts[2].id)).lines.single.quantity, 1);

    container.read(selectedInvoiceSessionIdProvider.notifier).state = drafts[0].id;
    expect(identical(container.read(invoicesRepositoryProvider), targetA), isTrue);

    Future<Object> checkout() async {
      try {
        return await targetB.checkoutInvoice();
      } catch (error) {
        return error;
      }
    }
    final results = await Future.wait([checkout(), checkout()]);
    expect(results.whereType<InvoiceDraft>(), hasLength(1));
    expect(results.whereType<StateError>(), hasLength(1));
    final ids = (await sessions.fetchActiveSessions()).map((draft) => draft.id);
    expect(ids, containsAll([drafts[0].id, drafts[2].id]));
    expect(ids, isNot(contains(drafts[1].id)));

    await SalonDatabase.instance.close();
    await SalonDatabase.instance.initialize(preserveExistingTestDatabase: true);
    final restarted = ProviderContainer();
    addTearDown(restarted.dispose);
    final restored = await restarted.read(activeInvoiceSessionsProvider.future);
    expect(restored.map((draft) => draft.id), containsAll([drafts[0].id, drafts[2].id]));
    expect((await sessions.fetchSession(drafts[0].id)).lines.single.quantity, 2);
  });

  testWidgets('POS switches A/B/C, creates a walk-in and opens appointments independently',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      try {
      final fixture = await _createFixture(3);
      final sessions = SqliteBillingSessionsRepository(SalonDatabase.instance);
      final drafts = <InvoiceDraft>[];
      for (final appointment in fixture.appointments) {
        drafts.add(await sessions.openAppointmentSession(appointment));
      }

      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint(details.toString());
        previousErrorHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousErrorHandler);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(SalonThemeTemplate.salonNoirGold),
          home: Scaffold(body: Column(children: [
          Consumer(builder: (context, ref, _) => TextButton(
            key: const Key('test-open-appointment'),
            onPressed: () => openAppointmentInvoice(ref, fixture.appointments[2]),
            child: const Text('Mở lịch C'),
          )),
          const Expanded(child: InvoicesPage()),
        ]))),
      ));
      await _settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InvoicesPage)), listen: false,
      );

      expect(find.byKey(const Key('billing-sessions-bar')), findsOneWidget);
      for (final draft in drafts) {
        final selector = find.byKey(ValueKey(
          'billing-session-selector-${container.read(selectedInvoiceSessionIdProvider)}',
        ));
        await tester.tap(selector);
        await _settle(tester);
        await tester.tap(find.byKey(
          ValueKey('billing-session-choice-${draft.id}'),
        ).last);
        await _settle(tester);
        expect(container.read(selectedInvoiceSessionIdProvider), draft.id);
        expect((await container.read(invoiceDraftProvider.future)).appointmentId,
            draft.appointmentId);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.byKey(const Key('billing-new-walkin')));
      await _settleUntil(tester, () => !drafts.any((draft) =>
          draft.id == container.read(selectedInvoiceSessionIdProvider)));
      final walkInId = container.read(selectedInvoiceSessionIdProvider);
      expect(drafts.map((draft) => draft.id), isNot(contains(walkInId)));
      expect((await sessions.fetchActiveSessions()).map((draft) => draft.id),
          containsAll([...drafts.map((draft) => draft.id), walkInId]));

      await tester.tap(find.byKey(const Key('test-open-appointment')));
      await _settleUntil(tester, () =>
          container.read(selectedInvoiceSessionIdProvider) == drafts[2].id);
      expect(container.read(selectedInvoiceSessionIdProvider), drafts[2].id);
      expect((await sessions.fetchActiveSessions())
          .where((draft) => draft.appointmentId == fixture.appointments[2].id),
          hasLength(1));

      await tester.tap(find.byKey(const Key('billing-checkout-action')));
      await _settle(tester);
      expect(find.byKey(const Key('checkout-confirm-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('checkout-confirm-yes')));
      await _settle(tester);
      expect(find.byKey(const Key('checkout-success-dialog')), findsOneWidget);
      final remaining = (await sessions.fetchActiveSessions())
          .map((draft) => draft.id).toSet();
      expect(remaining, containsAll([drafts[0].id, drafts[1].id, walkInId]));
      expect(remaining, isNot(contains(drafts[2].id)));
      await tester.tap(find.widgetWithText(FilledButton, 'Hóa đơn mới'));
      await _settle(tester);

      for (final size in [const Size(1024, 768), const Size(1600, 900)]) {
        tester.view.physicalSize = size;
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: size.toString());
      }
      await tester.pumpWidget(const SizedBox.shrink());
      } catch (error, stack) {
        fail('Multi-bill UI failed: $error\n$stack');
      }
    });
    expect(tester.takeException(), isNull);
  });
}

Future<void> _settle(WidgetTester tester) async {
  // SQLite FFI and provider IO run on the real clock inside runAsync.
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
  await tester.pumpAndSettle();
}

Future<void> _settleUntil(WidgetTester tester, bool Function() completed) async {
  // Pump frames while SQLite FFI completes on the real clock. Animation
  // settling alone does not mean the asynchronous session mutation finished.
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!completed() && DateTime.now().isBefore(deadline)) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(completed(), isTrue, reason: 'Session mutation did not complete');
  await _settle(tester);
}

class _Fixture {
  const _Fixture({
    required this.appointments,
    required this.serviceId,
    required this.employeeId,
  });

  final List<AppointmentEntry> appointments;
  final String serviceId;
  final String employeeId;
}

Future<_Fixture> _createFixture(int appointmentCount) async {
  final database = await SalonDatabase.instance.database;
  final now = DateTime.now();

  const employeeId = 'emp-billing-session';
  const serviceId = 'svc-billing-session';
  const servicePrice = 240000;

  await database.insert('employees', {
    'id': employeeId,
    'full_name': 'Nhân viên billing session',
    'initials': 'BS',
    'role': 'Stylist',
    'status': 'Đang làm việc',
    'phone': '0901000001',
    'email': null,
    'shift_label': '09:00 - 18:00',
    'specialty': '',
    'commission_rate': 0,
    'commission_label': '',
    'today_schedule': '',
    'services_done': 0,
    'monthly_revenue_label': '',
    'rating_label': '5.0',
    'notes': '',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });

  await database.insert('services', {
    'id': serviceId,
    'name': 'Dịch vụ billing session',
    'category': 'Chăm sóc',
    'duration_minutes': 60,
    'price': servicePrice,
    'description': '',
    'is_active': 1,
    'popularity_label': 'Ổn định',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });

  final appointments = <AppointmentEntry>[];
  for (var index = 0; index < appointmentCount; index++) {
    final customerId = 'cust-billing-session-$index';
    final appointmentId = 'apt-billing-session-$index';
    final startsAt = now.add(Duration(minutes: index * 30));

    await database.insert('customers', {
      'id': customerId,
      'full_name': 'Khách billing $index',
      'phone': '09010001${index.toString().padLeft(2, '0')}',
      'email': null,
      'tier': 'Member',
      'loyalty_points': 0,
      'favorite_service': '',
      'last_visit_at': null,
      'hair_profile': '',
      'visit_count': 0,
      'total_spent': 0,
      'notes': '',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    await database.insert('appointments', {
      'id': appointmentId,
      'customer_id': customerId,
      'service_id': serviceId,
      'employee_id': employeeId,
      'starts_at': startsAt.toIso8601String(),
      'status': 'Đang làm',
      'note': '',
      'total_amount': servicePrice,
      'customer_name': 'Khách billing $index',
      'customer_phone': '09010001${index.toString().padLeft(2, '0')}',
      'service_name': 'Dịch vụ billing session',
      'staff_name': 'Nhân viên billing session',
      'duration_minutes': 60,
      'slot_label': 'Ghế ${index + 1}',
      'date_label': 'Hôm nay',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    appointments.add(
      AppointmentEntry(
        id: appointmentId,
        customerId: customerId,
        serviceId: serviceId,
        employeeId: employeeId,
        customerName: 'Khách billing $index',
        customerPhone: '09010001${index.toString().padLeft(2, '0')}',
        serviceName: 'Dịch vụ billing session',
        staffName: 'Nhân viên billing session',
        status: 'Đang làm',
        durationMinutes: 60,
        slotLabel: 'Ghế ${index + 1}',
        note: '',
        startsAt: startsAt,
        dateLabel: 'Hôm nay',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  return _Fixture(
    appointments: appointments,
    serviceId: serviceId,
    employeeId: employeeId,
  );
}
