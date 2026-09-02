import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/appointment_upsert_input.dart';
import 'package:salonmanager/core/models/customer_upsert_input.dart';
import 'package:salonmanager/core/models/employee_upsert_input.dart';
import 'package:salonmanager/core/models/service_upsert_input.dart';
import 'package:salonmanager/core/repositories/sqlite_appointments_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_customers_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_employees_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_services_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('cho phep tao lich khong trung', () async {
    final fixture = await _createFixture();

    await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );

    final second = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '10:00',
        durationMinutes: 60,
      ),
    );

    expect(second.id, isNotEmpty);
  });

  test('chan lich trung cung nhan vien', () async {
    final fixture = await _createFixture();

    await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );

    expect(
      () => fixture.appointmentsRepository.saveAppointment(
        fixture.buildInput(
          employeeId: fixture.employeeAId,
          timeLabel: '09:30',
          durationMinutes: 30,
        ),
      ),
      throwsA(
        predicate(
          (error) =>
              error is StateError &&
              error.toString().contains(
                'Nhân viên này đã có lịch trong khung giờ đã chọn.',
              ),
        ),
      ),
    );
  });

  test('cho phep trung gio neu khac nhan vien', () async {
    final fixture = await _createFixture();

    await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );

    final second = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeBId,
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );

    expect(second.employeeId, fixture.employeeBId);
  });

  test('bo qua lich da huy khi kiem tra conflict', () async {
    final fixture = await _createFixture();

    await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        status: 'Đã hủy',
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );

    final active = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        status: 'Đã đặt',
        timeLabel: '09:00',
        durationMinutes: 60,
      ),
    );

    expect(active.status, 'Đã đặt');
  });

  test('sua lich khong tu conflict voi chinh no', () async {
    final fixture = await _createFixture();

    final created = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '11:00',
        durationMinutes: 60,
      ),
    );

    final updated = await fixture.appointmentsRepository.saveAppointment(
      fixture.buildInput(
        employeeId: fixture.employeeAId,
        timeLabel: '11:00',
        durationMinutes: 60,
        note: 'Cap nhat ghi chu',
      ),
      existingId: created.id,
    );

    expect(updated.id, created.id);
    expect(updated.note, 'Cap nhat ghi chu');
  });
}

class _Fixture {
  const _Fixture({
    required this.appointmentsRepository,
    required this.customerId,
    required this.serviceAId,
    required this.employeeAId,
    required this.employeeBId,
  });

  final SqliteAppointmentsRepository appointmentsRepository;
  final String customerId;
  final String serviceAId;
  final String employeeAId;
  final String employeeBId;

  AppointmentUpsertInput buildInput({
    required String employeeId,
    required String timeLabel,
    required int durationMinutes,
    String status = 'Đã đặt',
    String note = '',
  }) {
    return AppointmentUpsertInput(
      customerId: customerId,
      serviceIds: [serviceAId],
      employeeId: employeeId,
      customerName: 'Khach test',
      customerPhone: '0900000000',
      serviceName: 'Dich vu test A',
      staffName: employeeId == employeeAId ? 'Nhan vien A' : 'Nhan vien B',
      status: status,
      durationMinutes: durationMinutes,
      slotLabel: 'Ghe test',
      note: note,
      dayLabel: 'Hôm nay',
      timeLabel: timeLabel,
    );
  }
}

Future<_Fixture> _createFixture() async {
  const fakeDataSource = FakeSalonDataSource();
  final appointmentsRepository = SqliteAppointmentsRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );
  final customersRepository = SqliteCustomersRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );
  final servicesRepository = SqliteServicesRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );
  final employeesRepository = SqliteEmployeesRepository(
    SalonDatabase.instance,
    fakeDataSource,
  );

  final customer = await customersRepository.saveCustomer(
    const CustomerUpsertInput(
      fullName: 'Khach test',
      phone: '0900000000',
      email: '',
      tier: 'Member',
      favoriteService: 'Dich vu test A',
      hairProfile: '',
      note: '',
    ),
  );

  final serviceA = await servicesRepository.saveService(
    const ServiceUpsertInput(
      name: 'Dich vu test A',
      category: 'Chăm sóc',
      durationMinutes: 60,
      price: 200000,
      description: '',
      isActive: true,
      popularityLabel: 'Ổn định',
    ),
  );

  final employeeA = await employeesRepository.saveEmployee(
    const EmployeeUpsertInput(
      fullName: 'Nhan vien A',
      role: 'Stylist',
      status: 'Đang làm việc',
      phone: '0900111111',
      shift: '09:00 - 18:00',
      specialty: 'Test',
      commissionLabel: '10%',
      todaySchedule: '',
      servicesDone: 0,
      monthlyRevenue: '',
      rating: '5.0',
      note: '',
    ),
  );

  final employeeB = await employeesRepository.saveEmployee(
    const EmployeeUpsertInput(
      fullName: 'Nhan vien B',
      role: 'Stylist',
      status: 'Đang làm việc',
      phone: '0900222222',
      shift: '09:00 - 18:00',
      specialty: 'Test',
      commissionLabel: '10%',
      todaySchedule: '',
      servicesDone: 0,
      monthlyRevenue: '',
      rating: '5.0',
      note: '',
    ),
  );

  return _Fixture(
    appointmentsRepository: appointmentsRepository,
    customerId: customer.id,
    serviceAId: serviceA.id,
    employeeAId: employeeA['id']!.toString(),
    employeeBId: employeeB['id']!.toString(),
  );
}
