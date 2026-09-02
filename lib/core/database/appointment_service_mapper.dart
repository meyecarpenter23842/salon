import '../models/appointment_service_line.dart';

class AppointmentServiceMapper {
  const AppointmentServiceMapper._();

  static AppointmentServiceLine fromDatabase(Map<String, Object?> row) {
    return AppointmentServiceLine(
      id: row['id'].toString(),
      appointmentId: row['appointment_id'].toString(),
      serviceId: row['service_id'].toString(),
      title: row['title'].toString(),
      quantity: _toInt(row['quantity']),
      unitPrice: _toInt(row['unit_price']),
      durationMinutes: _toInt(row['duration_minutes']),
    );
  }

  static Map<String, Object?> toDatabase(AppointmentServiceLine line) {
    return {
      'id': line.id,
      'appointment_id': line.appointmentId,
      'service_id': line.serviceId,
      'title': line.title,
      'quantity': line.quantity,
      'unit_price': line.unitPrice,
      'duration_minutes': line.durationMinutes,
    };
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
