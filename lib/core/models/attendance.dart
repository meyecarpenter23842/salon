
import 'dart:convert';

class AttendanceBreak {
  const AttendanceBreak(this.start, this.end);
  final DateTime start;
  final DateTime? end;
  Map<String, Object?> toJson() => {
    'start': start.millisecondsSinceEpoch,
    'end': end?.millisecondsSinceEpoch,
  };
}

class AttendanceShift {
  AttendanceShift(Map<String, Object?> row) : data = Map.unmodifiable(row);
  final Map<String, Object?> data;
  String get id => data['id'] as String;
  String get employeeId => data['employee_id'] as String;
  String get employeeName => data['employee_name'] as String;
  String get label => data['label'] as String;
  String get workDay => data['work_day'] as String;
  String get state => data['state'] as String;
  int get revision => data['revision'] as int;
  DateTime get plannedStart => DateTime.fromMillisecondsSinceEpoch(data['planned_start'] as int);
  DateTime get plannedEnd => DateTime.fromMillisecondsSinceEpoch(data['planned_end'] as int);
  DateTime? get clockIn => _date('clock_in');
  DateTime? get clockOut => _date('clock_out');
  DateTime? _date(String key) => data[key] == null ? null : DateTime.fromMillisecondsSinceEpoch(data[key] as int);
  List<AttendanceBreak> get breaks => (jsonDecode(data['breaks_json'] as String) as List)
    .map((b) => AttendanceBreak(DateTime.fromMillisecondsSinceEpoch(b['start'] as int),
      b['end'] == null ? null : DateTime.fromMillisecondsSinceEpoch(b['end'] as int))).toList();
  bool get onBreak => breaks.isNotEmpty && breaks.last.end == null;
  /// Only closed attendance contributes final worked time; never estimate wages.
  int? get workedSeconds => clockIn == null || clockOut == null ? null :
    clockOut!.difference(clockIn!).inSeconds -
      breaks.fold<int>(0, (sum, b) => sum + b.end!.difference(b.start).inSeconds);
  String get statusLabel => switch (state) {
    'planned' => 'Chưa vào ca',
    'working' => onBreak ? 'Đang nghỉ' : 'Đang làm',
    'completed' => 'Đã ra ca',
    'leave' => 'Nghỉ ca',
    _ => 'Đã hủy ca',
  };
}

class AttendanceSnapshot {
  const AttendanceSnapshot(this.employees, this.shifts);
  final List<Map<String, Object?>> employees;
  final List<AttendanceShift> shifts;
}
