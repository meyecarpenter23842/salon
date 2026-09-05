import '../models/appointment_entry.dart';
import 'customer_mapper.dart';

class AppointmentMapper {
  const AppointmentMapper._();

  static AppointmentEntry fromDatabase(Map<String, Object?> row) {
    final startsAt = _parseDateTime(row['starts_at']) ?? DateTime.now();
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
      startsAt: startsAt,
      dateLabel: dateKey(startsAt),
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
      dateLabel: dateKey(startsAt),
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
      'date_label': appointment.dateKey,
      'created_at': appointment.createdAt.toIso8601String(),
      'updated_at': appointment.updatedAt.toIso8601String(),
    };
  }

  static bool isValidTimeLabel(String value) {
    return RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value.trim());
  }

  static String dateKey(DateTime date) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-${twoDigits(date.month)}-${twoDigits(date.day)}';
  }

  static String relativeDayLabel(
    DateTime date, {
    DateTime? referenceTime,
  }) {
    final reference = referenceTime ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final appointmentDay = DateTime(date.year, date.month, date.day);
    final difference = appointmentDay.difference(today).inDays;
    if (difference == 0) return 'Hôm nay';
    if (difference == 1) return 'Ngày mai';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';
  }

  static bool matchesDayFilter(
    DateTime startsAt,
    String dayLabel, {
    DateTime? referenceTime,
  }) {
    if (dayLabel == 'Tất cả') return true;
    return relativeDayLabel(startsAt, referenceTime: referenceTime) == dayLabel;
  }

  static DateTime buildStartsAt({
    required String dateLabel,
    required String timeLabel,
    DateTime? referenceTime,
  }) {
    final normalizedTime = timeLabel.trim();
    if (!isValidTimeLabel(normalizedTime)) {
      throw StateError('Giờ hẹn không hợp lệ. Dùng HH:mm trong khoảng 00:00–23:59.');
    }

    final reference = referenceTime ?? DateTime.now();
    final today = DateTime(reference.year, reference.month, reference.day);
    final normalizedDate = dateLabel.trim();
    final date = switch (normalizedDate) {
      'Hôm nay' => today,
      'Ngày mai' => DateTime(today.year, today.month, today.day + 1),
      _ => _parseAbsoluteDate(normalizedDate),
    };
    if (date == null) {
      throw StateError('Ngày hẹn không hợp lệ.');
    }

    final timeParts = normalizedTime.split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  static DateTime? _parseAbsoluteDate(String value) {
    final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (isoMatch != null) {
      return _validatedDate(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
      );
    }

    final displayMatch = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(value);
    if (displayMatch != null) {
      return _validatedDate(
        int.parse(displayMatch.group(3)!),
        int.parse(displayMatch.group(2)!),
        int.parse(displayMatch.group(1)!),
      );
    }
    return null;
  }

  static DateTime? _validatedDate(int year, int month, int day) {
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
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
