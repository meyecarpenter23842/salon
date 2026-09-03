part of 'appointments_page.dart';

List<int> _dayBoardSlots(
  List<AppointmentEntry> items,
  List<Map<String, Object?>> employees,
) {
  var earliest = 24 * 60;
  var latest = 0;

  if (items.isNotEmpty) {
    for (final item in items) {
      final start = item.startsAt.hour * 60 + item.startsAt.minute;
      final end = item.endsAt.hour * 60 +
          item.endsAt.minute +
          (item.endsAt.day != item.startsAt.day ? 24 * 60 : 0);
      if (start < earliest) earliest = start;
      if (end > latest) latest = end;
    }
    final firstSlot =
        ((_floorHalfHour(earliest) - 30).clamp(0, 24 * 60 - 30)).toInt();
    final lastSlot =
        ((_ceilHalfHour(latest) + 30).clamp(firstSlot + 30, 24 * 60))
            .toInt();
    return [
      for (var minute = firstSlot; minute < lastSlot; minute += 30) minute,
    ];
  }

  for (final employee in employees) {
    final range = _parseShiftRange(employee['shift']?.toString() ?? '');
    if (range == null) continue;
    if (range.$1 < earliest) earliest = range.$1;
    if (range.$2 > latest) latest = range.$2;
  }

  if (earliest >= latest) {
    earliest = 9 * 60;
    latest = 18 * 60;
  }

  final firstSlot =
      _floorHalfHour(earliest).clamp(0, 24 * 60 - 30).toInt();
  final lastSlot =
      _ceilHalfHour(latest).clamp(firstSlot + 30, 24 * 60).toInt();
  return [
    for (var minute = firstSlot; minute < lastSlot; minute += 30) minute,
  ];
}

(int, int)? _parseShiftRange(String raw) {
  final matches = RegExp(r'(\d{1,2}):(\d{2})').allMatches(raw).toList();
  if (matches.length < 2) return null;
  int toMinutes(RegExpMatch match) {
    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return -1;
    }
    return hour * 60 + minute;
  }

  final start = toMinutes(matches[0]);
  final end = toMinutes(matches[1]);
  if (start < 0 || end <= start) return null;
  return (start, end);
}

List<AppointmentEntry> _appointmentsForCell({
  required List<AppointmentEntry> items,
  required Map<String, Object?> employee,
  required int slotMinutes,
}) {
  final results = items.where((appointment) {
    final startMinutes =
        appointment.startsAt.hour * 60 + appointment.startsAt.minute;
    return _floorHalfHour(startMinutes) == slotMinutes &&
        _matchesEmployee(appointment, employee);
  }).toList(growable: false);
  results.sort((a, b) {
    if (a.status == 'Đã hủy' && b.status != 'Đã hủy') return 1;
    if (a.status != 'Đã hủy' && b.status == 'Đã hủy') return -1;
    return a.startsAt.compareTo(b.startsAt);
  });
  return results;
}

bool _matchesEmployee(
  AppointmentEntry appointment,
  Map<String, Object?> employee,
) {
  final employeeId = employee['id']?.toString();
  if (appointment.employeeId != null &&
      appointment.employeeId == employeeId) {
    return true;
  }
  final employeeName =
      employee['name']?.toString().trim().toLowerCase() ?? '';
  return employeeName.isNotEmpty &&
      appointment.staffName.trim().toLowerCase() == employeeName;
}

int _floorHalfHour(int minutes) => (minutes ~/ 30) * 30;
int _ceilHalfHour(int minutes) => ((minutes + 29) ~/ 30) * 30;

String _minutesLabel(int minutes) {
  if (minutes >= 24 * 60) return '24:00';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return '${hours.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}
