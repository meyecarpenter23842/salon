import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/appointment_entry.dart';
import 'package:salonmanager/core/models/invoice_draft.dart';
import 'package:salonmanager/core/repositories/sqlite_billing_sessions_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test(
    'appointment billing sessions survive restart and checkout independently',
    () async {
      final fixture = await _createFixture(3);
      final repository = SqliteBillingSessionsRepository(
        SalonDatabase.instance,
      );

      final sessionA = await repository.openAppointmentSession(
        fixture.appointments[0],
      );
      final sessionB = await repository.openAppointmentSession(
        fixture.appointments[1],
      );
      final sessionC = await repository.openAppointmentSession(
        fixture.appointments[2],
      );

      expect(
        {sessionA.id, sessionB.id, sessionC.id},
        hasLength(3),
      );
      expect(sessionA.lines.single.quantity, 1);
      expect(sessionB.lines.single.quantity, 1);
      expect(sessionC.lines.single.quantity, 1);

      final reopenedA = await repository.openAppointmentSession(
        fixture.appointments[0],
      );
      expect(reopenedA.id, sessionA.id);

      final updatedA = await repository.addService(
        sessionA.id,
        fixture.serviceId,
        employeeId: fixture.employeeId,
      );
      expect(updatedA.lines.single.quantity, 2);
      expect(
        (await repository.fetchSession(sessionB.id)).lines.single.quantity,
        1,
      );

      await SalonDatabase.instance.close();
      await SalonDatabase.instance.initialize(
        preserveExistingTestDatabase: true,
      );

      final restarted = SqliteBillingSessionsRepository(
        SalonDatabase.instance,
      );
      final activeAfterRestart = await restarted.fetchActiveSessions();
      final activeIds = activeAfterRestart.map((draft) => draft.id).toSet();
      expect(
        activeIds,
        containsAll(<String>[sessionA.id, sessionB.id, sessionC.id]),
      );
      expect(
        (await restarted.fetchSession(sessionA.id)).lines.single.quantity,
        2,
      );

      await restarted.checkout(sessionB.id);

      final remainingIds = (await restarted.fetchActiveSessions())
          .map((draft) => draft.id)
          .toSet();
      expect(remainingIds, contains(sessionA.id));
      expect(remainingIds, isNot(contains(sessionB.id)));
      expect(remainingIds, contains(sessionC.id));

      final history = await SqliteInvoicesRepository(
        SalonDatabase.instance,
      ).fetchRecentInvoices(
        appointmentId: fixture.appointments[1].id,
      );
      expect(history, hasLength(1));
      expect(history.single.isPaid, isTrue);
    },
  );

  test('walk-in sessions and the legacy draft persist independently', () async {
    final fixture = await _createFixture(1);
    final repository = SqliteBillingSessionsRepository(
      SalonDatabase.instance,
    );

    final walkInA = await repository.createWalkInSession();
    final walkInB = await repository.createWalkInSession();
    expect(walkInA.id, isNot(walkInB.id));

    await repository.addService(walkInA.id, fixture.serviceId);
    await repository.addService(walkInB.id, fixture.serviceId);
    await repository.addService(walkInB.id, fixture.serviceId);

    final legacyRepository = SqliteInvoicesRepository(SalonDatabase.instance);
    await legacyRepository.addInvoiceService(fixture.serviceId);

    await SalonDatabase.instance.close();
    await SalonDatabase.instance.initialize(
      preserveExistingTestDatabase: true,
    );

    final restarted = SqliteBillingSessionsRepository(
      SalonDatabase.instance,
    );
    final activeIds = (await restarted.fetchActiveSessions())
        .map((draft) => draft.id)
        .toSet();

    expect(
      activeIds,
      containsAll(<String>[
        walkInA.id,
        walkInB.id,
        SqliteInvoicesRepository.legacyDraftInvoiceId,
      ]),
    );
    expect(
      (await restarted.fetchSession(walkInA.id)).lines.single.quantity,
      1,
    );
    expect(
      (await restarted.fetchSession(walkInB.id)).lines.single.quantity,
      2,
    );
    expect(
      (await restarted.fetchSession(
        SqliteInvoicesRepository.legacyDraftInvoiceId,
      ))
          .lines
          .single
          .quantity,
      1,
    );
  });

  test('same billing session rejects concurrent double checkout', () async {
    final fixture = await _createFixture(1);
    final repository = SqliteBillingSessionsRepository(
      SalonDatabase.instance,
    );
    final session = await repository.openAppointmentSession(
      fixture.appointments.single,
    );

    Future<Object> attemptCheckout() async {
      try {
        return await repository.checkout(session.id);
      } catch (error) {
        return error;
      }
    }

    final results = await Future.wait<Object>([
      attemptCheckout(),
      attemptCheckout(),
    ]);

    expect(results.whereType<InvoiceDraft>(), hasLength(1));
    expect(results.whereType<StateError>(), hasLength(1));

    final history = await SqliteInvoicesRepository(
      SalonDatabase.instance,
    ).fetchRecentInvoices(
      appointmentId: fixture.appointments.single.id,
    );
    expect(history, hasLength(1));
  });
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
