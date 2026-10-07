import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/models/payroll.dart';
import '../../../../core/models/entity_id.dart';
import '../../../../core/repositories/sqlite_payroll_repository.dart';

class SalaryPolicyInput {
  const SalaryPolicyInput(
    this.employeeId,
    this.period,
    this.mode,
    this.rate,
    this.minutes,
    this.reason,
  );
  final String employeeId, period, mode, reason;
  final int rate, minutes;
}

class SalaryPolicyDialog extends StatefulWidget {
  const SalaryPolicyDialog({
    super.key,
    required this.employees,
    required this.policies,
    required this.period,
  });
  final List<Map<String, Object?>> employees, policies;
  final String period;
  @override
  State<SalaryPolicyDialog> createState() => _SalaryPolicyDialogState();
}

class _SalaryPolicyDialogState extends State<SalaryPolicyDialog> {
  String? employeeId, error;
  String mode = 'fixed';
  final rate = TextEditingController(),
      hours = TextEditingController(),
      reason = TextEditingController();
  late TextEditingController period;
  @override
  void initState() {
    super.initState();
    period = TextEditingController(text: widget.period);
  }

  @override
  void dispose() {
    rate.dispose();
    hours.dispose();
    reason.dispose();
    period.dispose();
    super.dispose();
  }

  void select(String? id) {
    setState(() {
      employeeId = id;
      final policy = widget.policies
          .where((p) => p['employee_id'] == id)
          .firstOrNull;
      mode = policy?['mode'] as String? ?? 'fixed';
      rate.text = policy?['rate']?.toString() ?? '';
      final minutes = policy?['standard_minutes'] as int? ?? 0;
      hours.text = minutes > 0 ? (minutes / 60).toString() : '';
    });
  }

  void save() {
    try {
      SqlitePayrollRepository.validatePeriod(period.text.trim());
      final amount = int.tryParse(rate.text),
          hour = double.tryParse(hours.text.replaceAll(',', '.'));
      final minutes = mode == 'monthly_work' && hour != null
          ? (hour * 60).round()
          : 0;
      if (employeeId == null ||
          amount == null ||
          reason.text.trim().isEmpty ||
          (mode == 'monthly_work' &&
              (hour == null ||
                  !hour.isFinite ||
                  hour <= 0 ||
                  minutes > 600000 ||
                  (hour * 60 - minutes).abs() > 0.00001))) {
        throw ArgumentError(
          'Chọn nhân viên, nhập lương, công chuẩn và lý do hợp lệ.',
        );
      }
      payrollBase(mode, amount, 0, minutes);
      Navigator.pop(
        context,
        SalaryPolicyInput(
          employeeId!,
          period.text.trim(),
          mode,
          amount,
          minutes,
          reason.text.trim(),
        ),
      );
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Thiết lập lương nhân viên'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Chọn cách tính riêng cho từng người. Mỗi lần lưu tạo một phiên bản; kỳ đã chốt giữ nguyên.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: employeeId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Nhân viên'),
              items: widget.employees
                  .map(
                    (e) => DropdownMenuItem(
                      value: e['id'] as String,
                      child: Text(e['full_name'] as String),
                    ),
                  )
                  .toList(),
              onChanged: select,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(mode),
              initialValue: mode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Cách tính lương'),
              items: ['fixed', 'monthly_work', 'hourly']
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(payrollModeLabel(m)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => mode = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rate,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: mode == 'hourly'
                    ? 'Đơn giá mỗi giờ (đ)'
                    : 'Lương tháng (đ)',
              ),
            ),
            if (mode == 'monthly_work') ...[
              const SizedBox(height: 12),
              TextField(
                controller: hours,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Giờ chuẩn tháng',
                  hintText: 'Ví dụ: 200',
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Lương tháng × giờ thực làm / giờ chuẩn, tối đa lương tháng. Giờ vượt chuẩn hiển thị riêng.',
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: period,
              decoration: const InputDecoration(
                labelText: 'Kỳ bắt đầu hiệu lực (YYYY-MM)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Lý do thiết lập/thay đổi',
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(onPressed: save, child: const Text('Lưu chính sách')),
    ],
  );
}

class PayrollItemInput {
  const PayrollItemInput(this.kind, this.amount, this.reason, this.source);
  final String kind, reason;
  final int amount;
  final String? source;
}

class PayrollItemDialog extends StatefulWidget {
  const PayrollItemDialog({super.key, required this.sources, this.reversal});
  final List<Map<String, Object?>> sources;
  final Map<String, Object?>? reversal;
  @override
  State<PayrollItemDialog> createState() => _PayrollItemDialogState();
}

class _PayrollItemDialogState extends State<PayrollItemDialog> {
  String kind = 'allowance';
  String? source, error;
  bool decrease = false;
  final amount = TextEditingController(), reason = TextEditingController();
  @override
  void dispose() {
    amount.dispose();
    reason.dispose();
    super.dispose();
  }

  void save() {
    final input = int.tryParse(amount.text);
    if (reason.text.trim().isEmpty ||
        (widget.reversal == null &&
            (input == null ||
                input <= 0 ||
                input > payrollMoneyLimit ||
                (kind == 'correction' && source == null)))) {
      setState(() => error = 'Nhập số tiền, lý do và kỳ gốc nếu điều chỉnh.');
      return;
    }
    final value = widget.reversal != null
        ? -(widget.reversal!['amount'] as int)
        : input! *
              ((kind == 'deduction' || (kind == 'correction' && decrease))
                  ? -1
                  : 1);
    Navigator.pop(
      context,
      PayrollItemInput(
        widget.reversal != null ? 'reversal' : kind,
        value,
        reason.text.trim(),
        widget.reversal != null ? null : source,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.reversal == null ? 'Thêm khoản lương' : 'Bỏ khoản đã nhập',
    ),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.reversal == null) ...[
              DropdownButtonFormField<String>(
                initialValue: kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Loại khoản'),
                items: const [
                  DropdownMenuItem(
                    value: 'allowance',
                    child: Text('Phụ cấp / thưởng'),
                  ),
                  DropdownMenuItem(value: 'deduction', child: Text('Khấu trừ')),
                  DropdownMenuItem(
                    value: 'correction',
                    child: Text('Điều chỉnh kỳ đã chốt trước đó'),
                  ),
                ],
                onChanged: (v) => setState(() => kind = v!),
              ),
              const SizedBox(height: 12),
              if (kind == 'correction') ...[
                DropdownButtonFormField<String>(
                  initialValue: source,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kỳ gốc đã chốt',
                  ),
                  items: widget.sources
                      .map(
                        (r) => DropdownMenuItem(
                          value: r['id'] as String,
                          child: Text(r['period'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => source = v,
                ),
                CheckboxListTile(
                  value: decrease,
                  onChanged: (v) => setState(() => decrease = v ?? false),
                  title: const Text('Điều chỉnh giảm lương'),
                ),
              ],
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Số tiền (đ)'),
              ),
            ] else
              Text(
                'Ghi khoản đảo để bỏ: ${widget.reversal!['reason']}. Lịch sử vẫn được giữ.',
              ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Lý do (bắt buộc)'),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(onPressed: save, child: const Text('Lưu khoản')),
    ],
  );
}

class PayrollPaymentDialog extends StatefulWidget {
  const PayrollPaymentDialog({
    super.key,
    required this.repository,
    required this.run,
    this.pending,
  });
  final SqlitePayrollRepository repository;
  final PayrollView run;
  final Map<String, Object?>? pending;
  @override
  State<PayrollPaymentDialog> createState() => _PayrollPaymentDialogState();
}

class _PayrollPaymentDialogState extends State<PayrollPaymentDialog> {
  late final String requestId;
  late String method;
  late final bool advance;
  late final TextEditingController amount, reference, note;
  bool busy = false, submitted = false, confirmed = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final p = widget.pending;
    requestId =
        p?['requestId'] as String? ?? EntityId.create('payroll_payment');
    method = p?['method'] as String? ?? 'transfer';
    advance = p?['advance'] as bool? ?? !widget.run.closed;
    amount = TextEditingController(
      text:
          p?['amount']?.toString() ??
          (advance ? '' : widget.run.balance.toString()),
    );
    reference = TextEditingController(text: p?['reference'] as String? ?? '');
    note = TextEditingController(text: p?['note'] as String? ?? '');
    submitted = p != null;
    confirmed = p != null;
  }

  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> pay() async {
    if (busy) {
      return;
    }
    final value = int.tryParse(amount.text);
    if (value == null ||
        value <= 0 ||
        value > payrollMoneyLimit ||
        !confirmed ||
        (method == 'transfer' && reference.text.trim().isEmpty)) {
      setState(
        () => error = 'Nhập số tiền, mã chuyển khoản và xác nhận tiền đã trả.',
      );
      return;
    }
    setState(() => busy = true);
    final oldRevision = widget.pending?['revision'] as int?;
    final original = oldRevision == null
        ? widget.run
        : PayrollView(
            row: Map<String, Object?>.from(widget.run.row)
              ..['revision'] = oldRevision,
            snapshot: widget.run.snapshot,
            items: widget.run.items,
            payouts: widget.run.payouts,
            policyHistory: widget.run.policyHistory,
            sourceChanged: widget.run.sourceChanged,
            commissionBalance: widget.run.commissionBalance,
          );
    submitted = true;
    try {
      await widget.repository.pay(
        requestId: requestId,
        run: original,
        amount: value,
        method: method,
        advance: advance,
        reference: reference.text,
        note: note.text,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> resolve() async {
    setState(() => busy = true);
    try {
      await widget.repository.resolvePending(requestId);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(
        '${advance ? 'Tạm ứng' : 'Ghi trả lương'} · ${widget.run.name}',
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Kỳ ${widget.run.period}. Chỉ ghi nhận tiền đã chi; hoa hồng vẫn trả riêng.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                enabled: !busy && !submitted,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Số tiền đã trả (đ)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: method,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Hình thức'),
                items: const [
                  DropdownMenuItem(
                    value: 'transfer',
                    child: Text('Chuyển khoản'),
                  ),
                  DropdownMenuItem(value: 'cash', child: Text('Tiền mặt')),
                ],
                onChanged: busy || submitted
                    ? null
                    : (v) => setState(() => method = v!),
              ),
              if (method == 'transfer') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: reference,
                  enabled: !busy && !submitted,
                  decoration: const InputDecoration(
                    labelText: 'Mã giao dịch (thêm ngân hàng nếu cần)',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: note,
                enabled: !busy && !submitted,
                decoration: const InputDecoration(labelText: 'Ghi chú'),
              ),
              CheckboxListTile(
                value: confirmed,
                onChanged: busy || submitted
                    ? null
                    : (v) => setState(() => confirmed = v ?? false),
                title: const Text(
                  'Đã chi tiền / đã chuyển khoản cho nhân viên',
                ),
              ),
              if (submitted)
                const Text(
                  'Đối chiếu yêu cầu này trước khi tạo khoản trả khác.',
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
        if (submitted)
          TextButton(
            onPressed: busy ? null : resolve,
            child: const Text('Đối chiếu sổ và bỏ yêu cầu'),
          ),
        FilledButton(
          onPressed: busy ? null : pay,
          child: Text(submitted ? 'Thử lại cùng yêu cầu' : 'Ghi nhận đã trả'),
        ),
      ],
    ),
  );
}

