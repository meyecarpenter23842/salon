import 'dart:convert';
import 'dart:math' as math;

const payrollMoneyLimit = 9000000000000;
String payrollModeLabel(String mode) => switch (mode) {
  'fixed' => 'Lương tháng cố định',
  'monthly_work' => 'Lương tháng theo công chuẩn',
  _ => 'Lương theo giờ',
};

/// Integer VND, half-up rounding once per employee/period.
int payrollBase(String mode, int rate, int workedSeconds, int standardMinutes) {
  if (rate < 0 ||
      rate > payrollMoneyLimit ||
      workedSeconds < 0 ||
      standardMinutes < 0 ||
      !['fixed', 'monthly_work', 'hourly'].contains(mode) ||
      (mode == 'monthly_work' && standardMinutes == 0)) {
    throw ArgumentError('Chính sách lương hoặc giờ công không hợp lệ.');
  }
  if (mode == 'fixed') {
    return rate;
  }
  final denominator = mode == 'hourly' ? 3600 : standardMinutes * 60;
  final seconds = mode == 'hourly'
      ? workedSeconds
      : math.min(workedSeconds, denominator);
  final numerator = BigInt.from(rate) * BigInt.from(seconds);
  final divisor = BigInt.from(denominator);
  final rounded =
      (numerator * BigInt.from(2) + divisor) ~/ (divisor * BigInt.from(2));
  if (rounded > BigInt.from(payrollMoneyLimit)) {
    throw ArgumentError('Tiền lương vượt giới hạn.');
  }
  return rounded.toInt();
}

class PayrollView {
  const PayrollView({
    required this.row,
    required this.snapshot,
    required this.items,
    required this.payouts,
    required this.policyHistory,
    required this.sourceChanged,
    required this.commissionBalance,
  });
  final Map<String, Object?> row, snapshot;
  final List<Map<String, Object?>> items, payouts, policyHistory;
  final bool sourceChanged;
  final int commissionBalance;
  String get id => row['id'] as String;
  String get employeeId => row['employee_id'] as String;
  String get name => row['employee_name'] as String;
  String get period => row['period'] as String;
  int get revision => row['revision'] as int;
  bool get closed => row['state'] == 'closed';
  int get base => snapshot['base'] as int;
  int get extras => snapshot['extras'] as int;
  int get net => snapshot['net'] as int;
  int get seconds => snapshot['worked_seconds'] as int;
  int get unresolved => snapshot['unresolved'] as int;
  int get paid => payouts.fold<int>(0, (sum, r) => sum + (r['amount'] as int));
  int get balance => net - paid;
  String get previewSignature => jsonEncode(snapshot);
  Map<String, Object?> get policy =>
      Map<String, Object?>.from(snapshot['policy'] as Map);
}

class PayrollWorkspace {
  const PayrollWorkspace(
    this.employees,
    this.policies,
    this.runs,
    this.pending,
  );
  final List<Map<String, Object?>> employees, policies;
  final List<PayrollView> runs;
  final Map<String, Object?>? pending;
}


String payrollItemLabel(String kind) => switch (kind) {
  'allowance' => 'Phụ cấp / thưởng',
  'deduction' => 'Khấu trừ',
  'correction' => 'Điều chỉnh kỳ trước',
  'reversal' => 'Đảo khoản đã nhập',
  _ => kind,
};
String payrollOperationLabel(String operation) => switch (operation) {
  'policy' => 'Thiết lập lương',
  'create' => 'Lập kỳ nháp',
  'item' => 'Ghi khoản lương',
  'close' => 'Chốt kỳ',
  'pay' => 'Ghi nhận đã trả',
  _ => operation,
};
