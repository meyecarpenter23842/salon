import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/models/entity_id.dart';
import '../../../core/models/finance_workspace.dart';

String financeMoney(int value) =>
    '${NumberFormat.decimalPattern('vi_VN').format(value)} đ';
String financeDate(DateTime value) => DateFormat('dd/MM/yyyy').format(value);
String financeState(String state) => switch (state) {
  'paid' => 'Đã trả',
  'partial' => 'Trả một phần',
  'reversed' => 'Đã đảo',
  _ => 'Chưa trả',
};

class FinanceCreateInput {
  const FinanceCreateInput(
    this.entityId,
    this.date,
    this.amount,
    this.reason,
    this.payee,
    this.reference,
  );
  final String entityId, reason, payee, reference;
  final DateTime date;
  final int amount;
}

class FinanceCreateDialog extends StatefulWidget {
  const FinanceCreateDialog({
    super.key,
    required this.book,
    required this.entities,
  });
  final FinanceBook book;
  final List<Map<String, Object?>> entities;
  @override
  State<FinanceCreateDialog> createState() => _FinanceCreateDialogState();
}

class _FinanceCreateDialogState extends State<FinanceCreateDialog> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(),
      reason = TextEditingController(),
      payee = TextEditingController(),
      reference = TextEditingController();
  String? entity;
  DateTime date = DateUtils.dateOnly(DateTime.now());
  @override
  void dispose() {
    for (final c in [amount, reason, payee, reference]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.book == FinanceBook.expense
          ? 'Lập khoản chi phí'
          : 'Nhập số dư đầu kỳ NCC',
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.book == FinanceBook.expense
                    ? 'Ghi nghĩa vụ phải trả, chưa chi tiền. Thanh toán tại chi tiết sau khi lưu.'
                    : 'Chỉ nhập nợ cũ đã đối chiếu. PN mới sinh nợ khi ghi kho; không nhập lại thành số dư đầu kỳ.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: entity,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: widget.book == FinanceBook.expense
                      ? 'Loại chi phí'
                      : 'Nhà cung cấp',
                ),
                items: widget.entities
                    .where((e) => e['is_active'] == 1)
                    .map(
                      (e) => DropdownMenuItem(
                        value: e['id'] as String,
                        child: Text(
                          e['name'] as String,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => entity = v,
                validator: (v) => v == null ? 'Chọn danh mục đang dùng' : null,
              ),
              TextButton.icon(
                onPressed: () async {
                  final next = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (next != null && mounted) {
                    setState(() => date = next);
                  }
                },
                icon: const Icon(Icons.calendar_month),
                label: Text('Ngày nghĩa vụ: ${financeDate(date)}'),
              ),
              TextFormField(
                key: const Key('finance-create-amount'),
                controller: amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Số tiền (đ)'),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return n == null || n <= 0 || n > 9000000000000
                      ? 'Số tiền phải từ 1 đến 9.000.000.000.000 đ'
                      : null;
                },
              ),
              if (widget.book == FinanceBook.expense)
                TextFormField(
                  controller: payee,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Người nhận / đối tác',
                  ),
                ),
              TextFormField(
                key: const Key('finance-create-reason'),
                controller: reason,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Lý do / nội dung',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Nhập lý do' : null,
              ),
              TextFormField(
                controller: reference,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Tham chiếu chứng từ gốc (nếu có)',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(
              context,
              FinanceCreateInput(
                entity!,
                date,
                int.parse(amount.text),
                reason.text.trim(),
                payee.text.trim(),
                reference.text.trim(),
              ),
            );
          }
        },
        child: const Text('Ghi nghĩa vụ'),
      ),
    ],
  );
}

/// One immutable request per money attempt. Reconciliation uses the same ID;
/// restart pending payload is never reconstructed from editable form fields.
class FinancePaymentDialog extends StatefulWidget {
  const FinancePaymentDialog({
    super.key,
    required this.book,
    required this.accounts,
    required this.submit,
    required this.resolve,
    this.pending,
    this.reversal,
  });
  final FinanceBook book;
  final List<FinanceAccount> accounts;
  final Map<String, Object?>? pending;
  final FinanceProof? reversal;
  final Future<void> Function(
    String id,
    String operation,
    Map<String, Object?> payload,
  )
  submit;
  final Future<bool> Function(String id) resolve;
  @override
  State<FinancePaymentDialog> createState() => _FinancePaymentDialogState();
}

class _FinancePaymentDialogState extends State<FinancePaymentDialog> {
  final form = GlobalKey<FormState>();
  final reference = TextEditingController(), note = TextEditingController();
  final amounts = <String, TextEditingController>{};
  late final String requestId;
  late final String operation;
  Map<String, Object?>? payload;
  String method = 'cash', error = '';
  bool confirmed = false, busy = false, uncertain = false, checked = false;
  @override
  void initState() {
    super.initState();
    requestId =
        widget.pending?['requestId'] as String? ??
        EntityId.create('finance_request');
    operation =
        widget.pending?['operation'] as String? ??
        (widget.reversal == null ? 'payment' : 'reversal');
    if (widget.pending != null) {
      payload = Map<String, Object?>.from(widget.pending!['payload'] as Map);
      uncertain = true;
    }
    method = payload?['method'] as String? ?? widget.reversal?.method ?? 'cash';
    reference.text = payload?['reference'] as String? ?? '';
    note.text =
        payload?[operation == 'reversal' ? 'reason' : 'note'] as String? ?? '';
    for (final a in widget.accounts) {
      amounts[a.id] = TextEditingController(
        text: a == widget.accounts.first ? '${a.balance}' : '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in [reference, note, ...amounts.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _edited() => setState(() => confirmed = false);
  Map<String, Object?> _input() => operation == 'reversal'
      ? {
          'paymentId': widget.reversal!.id,
          'reason': note.text.trim(),
          'reference': reference.text.trim(),
        }
      : widget.book == FinanceBook.expense
      ? {
          'expenseId': widget.accounts.single.id,
          'amount': int.parse(amounts.values.single.text),
          'method': method,
          'reference': reference.text.trim(),
          'note': note.text.trim(),
        }
      : {
          'supplierId': widget.accounts.first.entityId,
          'allocations': [
            for (final a in widget.accounts)
              if ((int.tryParse(amounts[a.id]!.text) ?? 0) > 0)
                {
                  'obligationId': a.id,
                  'amount': int.parse(amounts[a.id]!.text),
                },
          ],
          'method': method,
          'reference': reference.text.trim(),
          'note': note.text.trim(),
        };
  Future<void> _save() async {
    if (busy || !confirmed || uncertain) {
      return;
    }
    if (payload == null && !form.currentState!.validate()) {
      return;
    }
    if (payload == null &&
        operation == 'payment' &&
        amounts.values.every((c) => (int.tryParse(c.text) ?? 0) <= 0)) {
      setState(() => error = 'Nhập ít nhất một phân bổ dương.');
      return;
    }
    payload ??= _input();
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.submit(requestId, operation, payload!);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'Chưa xác nhận kết quả: $e';
          uncertain = true;
          checked = false;
          confirmed = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _resolve() async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    try {
      final found = await widget.resolve(requestId);
      if (!mounted) {
        return;
      }
      if (found) {
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        checked = true;
        uncertain = false;
        confirmed = false;
        error =
            'Đã đối chiếu: chưa ghi chứng từ. Kiểm tra tiền thật trước khi thử lại cùng yêu cầu; có thể đóng và tải lại số dư.';
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = 'Chưa đối chiếu được: $e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final frozen = payload != null;
    final total = operation == 'reversal'
        ? widget.reversal?.amount.abs()
        : amounts.values.fold<int>(
            0,
            (s, c) => s + (int.tryParse(c.text) ?? 0),
          );
    return AlertDialog(
      title: Text(
        operation == 'reversal' ? 'Đảo / hoàn chứng từ tiền' : 'Ghi thanh toán',
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText('Yêu cầu: $requestId'),
                if (frozen) ...[
                  const Text('Nội dung đã khóa theo yêu cầu gốc:'),
                  SelectableText('$payload'),
                ] else ...[
                  if (operation == 'payment')
                    for (final a in widget.accounts)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: TextFormField(
                          key: ValueKey('allocation-${a.id}'),
                          controller: amounts[a.id],
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText:
                                '${a.source} · còn ${financeMoney(a.balance)}',
                            helperText: a.name,
                          ),
                          onChanged: (_) => _edited(),
                          validator: (v) {
                            final n = int.tryParse(v ?? '') ?? 0;
                            return n < 0 ||
                                    n > a.balance ||
                                    (widget.book == FinanceBook.expense &&
                                        n == 0)
                                ? 'Phân bổ phải dương và không vượt số còn phải trả'
                                : null;
                          },
                        ),
                      ),
                  if (operation == 'reversal')
                    Text(
                      'Chứng từ gốc: ${widget.reversal!.id}\nHoàn ${financeMoney(widget.reversal!.amount)} qua ${method == 'cash' ? 'tiền mặt' : 'chuyển khoản'}. Hoàn toàn bộ phân bổ của chứng từ gốc.',
                    ),
                  if (operation == 'payment')
                    DropdownButtonFormField<String>(
                      initialValue: method,
                      decoration: const InputDecoration(
                        labelText: 'Nguồn tiền',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'cash',
                          child: Text('Tiền mặt · ca đang mở'),
                        ),
                        DropdownMenuItem(
                          value: 'transfer',
                          child: Text('Chuyển khoản · giao dịch bên ngoài'),
                        ),
                      ],
                      onChanged: busy
                          ? null
                          : (v) {
                              method = v!;
                              _edited();
                            },
                    ),
                  TextFormField(
                    controller: reference,
                    enabled: !busy,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Mã giao dịch / mã hoàn tiền',
                    ),
                    onChanged: (_) => _edited(),
                    validator: (v) =>
                        method == 'transfer' && (v ?? '').trim().isEmpty
                        ? 'Chuyển khoản bắt buộc mã giao dịch mới'
                        : null,
                  ),
                  TextFormField(
                    controller: note,
                    enabled: !busy,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      labelText: operation == 'reversal'
                          ? 'Lý do đảo / hoàn'
                          : 'Ghi chú',
                    ),
                    onChanged: (_) => _edited(),
                    validator: (v) =>
                        operation == 'reversal' && (v ?? '').trim().isEmpty
                        ? 'Nhập lý do'
                        : null,
                  ),
                  Text(
                    'Tổng ${financeMoney(total ?? 0)}. Tiền mặt ghi đúng một biến động ca; chuyển khoản chỉ ghi nhận tiền đã giao dịch bên ngoài.',
                  ),
                  if (operation == 'payment')
                    for (final a in widget.accounts)
                      Text(
                        '${a.source} · còn sau trả: ${financeMoney(a.balance - (int.tryParse(amounts[a.id]!.text) ?? 0))}',
                      ),
                ],
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (!uncertain)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: confirmed,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => confirmed = v!),
                    title: Text(
                      operation == 'reversal'
                          ? 'Đã nhận hoàn tiền thật / đã đối chiếu giao dịch đảo'
                          : 'Đã chi tiền thật / đã chuyển khoản, đúng phân bổ',
                    ),
                  ),
                if (busy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
        if (uncertain)
          FilledButton(
            onPressed: busy ? null : _resolve,
            child: const Text('Đối chiếu đúng requestId'),
          )
        else
          FilledButton(
            key: const Key('finance-payment-submit'),
            onPressed: busy || !confirmed ? null : _save,
            child: Text(checked ? 'Thử lại cùng yêu cầu' : 'Ghi chứng từ'),
          ),
      ],
    );
  }
}
