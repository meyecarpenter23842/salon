import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/models/appointment_entry.dart';

void main() {
  test('appointment exposes clear start and end time from duration', () {
    final startsAt = DateTime(2026, 9, 3, 9, 30);
    final appointment = AppointmentEntry(
      id: 'apt-v2-2',
      customerId: 'customer-v2-2',
      employeeId: 'employee-v2-2',
      customerName: 'Khách V2-2',
      customerPhone: '0900000000',
      serviceName: 'Dịch vụ V2-2',
      staffName: 'Nhân viên V2-2',
      status: 'Đã đặt',
      durationMinutes: 90,
      slotLabel: 'Ghế 1',
      note: '',
      startsAt: startsAt,
      dateLabel: 'Hôm nay',
      createdAt: startsAt,
      updatedAt: startsAt,
    );

    expect(appointment.endsAt, DateTime(2026, 9, 3, 11));
    expect(appointment.timeRangeLabel, '09:30–11:00');
  });
}
