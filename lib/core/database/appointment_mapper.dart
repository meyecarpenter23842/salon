import '../models/appointment_entry.dart';
import 'customer_mapper.dart';

class AppointmentMapper {
  const AppointmentMapper._();

  static AppointmentEntry fromDatabase(Map<String, Object?> row) {
    return AppointmentEntry(
      id: row['id'].toString(),
      customerId: row['customer_id'].toString(),
      serviceId: row['service_id']?.toString(),
      employeeId: row['employee_id']?.toString(),
      customerName: row['customer_name'].toString(),
      customerPhone: row['customer_phone'].toString(),
      serviceName: row['service_name'].toString(),
      staffName: row['staff_name'].toString(),
      status: row['status'].toString(),
      durationMinutes: _toInt(row['duration_minutes']),
      slotLabel: row['slot_label']?.toString() ?? '',
      note: row['note']?.toString() ?? '',
      startsAt: _parseDateTime(row['starts_at']) ?? DateTime.now(),
      dateLabel: row['date_label']?.toString() ?? '',
      createdAt: _parseDateTime(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDateTime(row['updated_at']) ?? DateTime.now(),
    );
  }

  static AppointmentEntry fromLegacyView(Map<String, Object?> data) {
    final startsAt = buildStartsAt(
      dateLabel: data['dateLabel'].toString(),
      timeLabel: data['time'].toString(),
    );
    final now = DateTime.now();

    return AppointmentEntry(
      id: data['id'].toString(),
      customerId: CustomerMapper.buildIdFromIdentity(
        fullName: data['customer'].toString(),
        phone: data['phone'].toString(),
      ),
      serviceId: data['serviceId']?.toString(),
      employeeId: data['employeeId']?.toString(),
      customerName: data['customer'].toString(),
      customerPhone: data['phone'].toString(),
      serviceName: data['service'].toString(),
      staffName: data['staff'].toString(),
      status: data['status'].toString(),
      durationMinutes: _parseDurationMinutes(data['duration'].toString()),
      slotLabel: data['slot'].toString(),
      note: data['note'].toString(),
      startsAt: startsAt,
      dateLabel: data['dateLabel'].toString(),
      createdAt: now,
      updatedAt: now,
    );
  }

  static Map<String, Object?> toDatabase(AppointmentEntry appointment) {
    return {
      'id': appointment.id,
      'customer_id': appointment.customerId,
      'service_id': appointment.serviceId,
      'employee_id': appointment.employeeId,
      'starts_at': appointment.startsAt.toIso8601String(),
      'status': appointment.status,
      'note': appointment.note,
      'total_amount': 0,
      'customer_name': appointment.customerName,
      'customer_phone': appointment.customerPhone,
      'service_name': appointment.serviceName,
      'staff_name': appointment.staffName,
      'duration_minutes': appointment.durationMinutes,
      'slot_label': appointment.slotLabel,
      'date_label': appointment.dateLabel,
      'created_at': appointment.createdAt.toIso8601String(),
      'updated_at': appointment.updatedAt.toIso8601String(),
    };
  }

  static DateTime buildStartsAt({
    required String dateLabel,
    required String timeLabel,
  }) {
    final today = DateTime.now();
    final date = switch (dateLabel) {
      'Ngày mai' => DateTime(today.year, today.month, today.day + 1),
      _ => DateTime(today.year, today.month, today.day),
    };
    final timeParts = timeLabel.split(':');
    final hour = int.tryParse(timeParts.first) ?? 0;
    final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static int _parseDurationMinutes(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  static DateTime? _parseDateTime(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) {
      return null;
    }

    return DateTime.tryParse(raw);
  }

  static int _toInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
