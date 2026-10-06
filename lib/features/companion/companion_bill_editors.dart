import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/lan/lan_health_client.dart';
import '../../core/lan/lan_workflow_client.dart';
import '../../core/lan/lan_workflow_models.dart';
import '../../core/lan/lan_write_contract.dart';
import 'companion_bill_ui.dart';
import 'companion_catalog_picker.dart';
import 'companion_command_controller.dart';
import 'companion_workspace.dart' show CompanionPendingNotice;

const billMethods = ['Tiền mặt', 'Chuyển khoản', 'Thẻ'];

class CompanionBillLineEditor extends StatefulWidget {
  const CompanionBillLineEditor({super.key, required this.snapshot, required this.line,
    required this.connection, required this.client, required this.commands, required this.role, required this.onDenied});
  final LanEditorSnapshot snapshot;
  final Map<String, dynamic> line;
  final LanConnection connection;
  final LanWorkflowClient client;
  final CompanionCommandController commands;
  final PhoneWriteRole role;
  final VoidCallback onDenied;
  @override State<CompanionBillLineEditor> createState() => _CompanionBillLineEditorState();
}
class _CompanionBillLineEditorState extends State<CompanionBillLineEditor> {
  final form = GlobalKey<FormState>();
  late final quantity = TextEditingController(text: '${widget.line['quantity']}');
  late final price = TextEditingController(text: '${widget.line['unitPrice']}');
  late Map<String, String> employee = widget.line['employeeId'] == null ? {} :
    {widget.line['employeeId'] as String: widget.line['employeeLabel']?.toString() ?? 'Nhân viên đã chọn'};
  late String original;
  bool allowExit = false, confirming = false, submitted = false, needsReload = false, completing = false;
  int observedGeneration = 0;
  bool get locked => widget.commands.blocked || widget.role == PhoneWriteRole.none;
  bool get dirty => jsonEncode(_payload()) != original;
  Map<String, dynamic> _payload() => {
    'lineId': widget.line['id'], 'quantity': int.tryParse(quantity.text.trim()) ?? 0,
    'employeeId': employee.keys.firstOrNull,
    if (widget.role == PhoneWriteRole.owner) 'unitPrice': int.tryParse(price.text.trim()) ?? 0,
  };
  @override void initState() { super.initState(); original = jsonEncode(_payload()); observedGeneration = widget.commands.dataGeneration; widget.commands.addListener(_changed); }
  void _changed() {
    if (!mounted) { return; }
    if (observedGeneration != widget.commands.dataGeneration) {
      observedGeneration = widget.commands.dataGeneration; needsReload = true;
    }
    if (submitted && !widget.commands.busy && widget.commands.pending == null) {
      if (widget.commands.lastResult?.type == 'session' && widget.commands.lastResult?.id == widget.snapshot.id) {
        _leave(true); return;
      }
      needsReload = true;
    }
    setState(() {});
  }
  void _leave(bool changed) {
    if (completing) { return; } completing = true; setState(() => allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) { Navigator.of(context).pop(changed); } });
  }
  Future<void> _back() async {
    if (confirming || widget.commands.busy) { return; }
    confirming = true;
    final leave = !dirty && widget.commands.pending == null || await confirmBillDiscard(context, pending: widget.commands.pending != null);
    confirming = false; if (mounted && leave) { _leave(false); }
  }
  Future<void> _employee() async {
    if (locked) { return; }
    final result = await Navigator.of(context).push<Map<String, String>>(MaterialPageRoute(builder: (_) =>
      CompanionCatalogPicker(connection: widget.connection, token: widget.commands.token, client: widget.client,
        kind: 'employees', epoch: widget.snapshot.epoch, onDenied: widget.onDenied, selected: employee)));
    if (mounted && result != null) { setState(() => employee = result); }
  }
  Future<void> _save() async {
    if (locked || needsReload || !form.currentState!.validate()) { return; }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => submitted = true);
    final result = await widget.commands.submit(LanWriteOperation.sessionUpdateLine, widget.snapshot, _payload());
    if (!mounted) { return; }
    if (result != null) { _leave(true); }
    else if (widget.commands.pending == null) { setState(() => needsReload = true); }
  }
  @override void dispose() {
    widget.commands.removeListener(_changed); quantity.dispose(); price.dispose(); super.dispose();
  }
  @override Widget build(BuildContext context) => PopScope(canPop: allowExit,
    onPopInvokedWithResult: (didPop, result) { if (!didPop) { _back(); } },
    child: Scaffold(appBar: AppBar(title: const Text('Chỉnh dòng bill'),
      leading: BackButton(onPressed: _back)),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.commands.message != null || widget.commands.pending != null) CompanionPendingNotice(commands: widget.commands),
        if (needsReload) const Padding(padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Dữ liệu có thể đã đổi. Quay lại bill để tải dữ liệu mới trước khi sửa tiếp.')),
        Form(key: form, child: billGroup(context, widget.line['title'] as String, [
          Text('Đơn giá hiện tại: ${billMoney(widget.line['unitPrice'] as int)}'),
          const SizedBox(height: 16),
          TextFormField(key: const Key('bill-line-quantity'), controller: quantity, enabled: !locked && !needsReload,
            maxLength: 4, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Số lượng', counterText: ''),
            validator: (v) { final n = int.tryParse(v?.trim() ?? ''); return n == null || n < 1 || n > 1000 ? 'Nhập số lượng từ 1 đến 1000.' : null; }),
          if (widget.role == PhoneWriteRole.owner) ...[
            const SizedBox(height: 16),
            TextFormField(key: const Key('bill-line-price'), controller: price, enabled: !locked && !needsReload,
              maxLength: 13, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Đơn giá (đ)', counterText: ''),
              validator: (v) { final n = int.tryParse(v?.trim() ?? ''); return n == null || n < 1 || n > 1000000000000 ? 'Nhập đơn giá từ 1 đến 1.000.000.000.000 đ.' : null; }),
          ],
          if (widget.line['isService'] == true) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(key: const Key('bill-line-employee'), onPressed: locked || needsReload ? null : _employee,
              icon: const Icon(Icons.badge_outlined), label: Text(employee.values.firstOrNull ?? 'Chọn nhân viên')),
            if (employee.isNotEmpty) TextButton(key: const Key('bill-line-clear-employee'),
              onPressed: locked || needsReload ? null : () => setState(() => employee = {}), child: const Text('Bỏ gán nhân viên')),
          ],
        ])),
      ])),
      bottomNavigationBar: Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: FilledButton(
          key: const Key('bill-line-save'), onPressed: locked || needsReload ? null : _save, child: const Text('Lưu dòng trên máy salon')))))));
}

class CompanionBillPaymentEditor extends StatefulWidget {
  const CompanionBillPaymentEditor({super.key, required this.total, required this.payments, required this.commands});
  final int total;
  final List<Map<String, dynamic>> payments;
  final CompanionCommandController commands;
  @override State<CompanionBillPaymentEditor> createState() => _CompanionBillPaymentEditorState();
}
class _CompanionBillPaymentEditorState extends State<CompanionBillPaymentEditor> {
  final form = GlobalKey<FormState>();
  late bool split = widget.payments.length > 1;
  late String method = billMethods.contains(widget.payments.firstOrNull?['method']) ? widget.payments.first['method'] as String : billMethods.first;
  late final amounts = {for (final m in billMethods) m: TextEditingController(text: '${widget.payments.where((p) => p['method'] == m).fold<int>(0, (sum, p) => sum + (p['amount'] as int))}')};
  late String original;
  bool allowExit = false, confirming = false;
  @override void initState() { super.initState(); original = _draftSignature(); }
  String _draftSignature() => jsonEncode({'split': split, 'method': method,
    'amounts': {for (final e in amounts.entries) e.key: e.value.text}});
  bool get dirty => _draftSignature() != original;
  int get allocated => split ? amounts.values.fold(0, (sum, c) => sum + (int.tryParse(c.text.trim()) ?? 0)) : widget.total;
  List<Map<String, dynamic>> _payments() => !split || widget.total == 0
    ? [{'method': method, 'amount': widget.total}]
    : [for (final entry in amounts.entries) if ((int.tryParse(entry.value.text.trim()) ?? 0) > 0)
      {'method': entry.key, 'amount': int.tryParse(entry.value.text.trim()) ?? 0}];
  Future<void> _back() async {
    if (confirming) { return; } confirming = true;
    final leave = !dirty || await confirmBillDiscard(context); confirming = false;
    if (mounted && leave) { _pop(null); }
  }
  void _pop(List<Map<String, dynamic>>? value) {
    setState(() => allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) { Navigator.of(context).pop(value); } });
  }
  @override void dispose() { for (final c in amounts.values) { c.dispose(); } super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: widget.commands, builder: (context, _) =>
    PopScope(canPop: allowExit, onPopInvokedWithResult: (didPop, result) { if (!didPop) { _back(); } },
      child: Scaffold(appBar: AppBar(title: const Text('Khoản thanh toán'), leading: BackButton(onPressed: _back)),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
          billGroup(context, 'Cần thanh toán', [Text(billMoney(widget.total), style: Theme.of(context).textTheme.headlineSmall)]),
          billGroup(context, 'Phương thức', [
            Wrap(spacing: 8, runSpacing: 8, children: [for (final m in billMethods) ChoiceChip(
              key: ValueKey('bill-method-$m'), label: Text(m), selected: method == m,
              onSelected: widget.commands.blocked ? null : (_) => setState(() => method = m))]),
            SwitchListTile(key: const Key('bill-payment-split'), contentPadding: EdgeInsets.zero,
              title: const Text('Chia nhiều khoản'), value: split,
              onChanged: widget.commands.blocked || widget.total == 0 ? null : (value) => setState(() {
                split = value;
                if (value && allocated == 0) { amounts[method]!.text = '${widget.total}'; }
              })),
          ]),
          if (split) Form(key: form, child: billGroup(context, 'Số tiền từng khoản', [
            for (final m in billMethods) Padding(padding: const EdgeInsets.only(bottom: 16), child: TextFormField(
              key: ValueKey('bill-payment-$m'), controller: amounts[m], enabled: !widget.commands.blocked,
              maxLength: 13, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: '$m (đ)', counterText: ''),
              validator: (v) { final n = int.tryParse(v?.trim() ?? ''); return n == null || n < 0 || n > 1000000000000 ? 'Nhập số tiền nguyên, không âm.' : null; })),
            billAmountRow('Đã phân bổ', billMoney(allocated)),
            Text(allocated == widget.total ? 'Đã phân bổ đủ.' : allocated < widget.total
              ? 'Còn thiếu ${billMoney(widget.total - allocated)}' : 'Đang dư ${billMoney(allocated - widget.total)}',
              key: const Key('bill-payment-balance'), style: TextStyle(color: allocated == widget.total ? Colors.green : Colors.red)),
          ])),
        ])),
        bottomNavigationBar: Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: FilledButton(
            key: const Key('bill-payment-done'), onPressed: widget.commands.blocked ? null : () {
              FocusManager.instance.primaryFocus?.unfocus();
              if (split && (!form.currentState!.validate() || allocated != widget.total)) { return; }
              _pop(_payments());
            }, child: const Text('Áp dụng và kiểm tra bill'))))))));
}

class CompanionBillAmountEditor extends StatefulWidget {
  const CompanionBillAmountEditor({super.key, required this.amount, required this.commands});
  final int amount;
  final CompanionCommandController commands;
  @override State<CompanionBillAmountEditor> createState() => _CompanionBillAmountEditorState();
}
class _CompanionBillAmountEditorState extends State<CompanionBillAmountEditor> {
  final form = GlobalKey<FormState>();
  late final amount = TextEditingController(text: '${widget.amount}');
  bool allowExit = false, confirming = false;
  Future<void> _back() async {
    if (confirming) { return; } confirming = true;
    final leave = amount.text == '${widget.amount}' || await confirmBillDiscard(context); confirming = false;
    if (mounted && leave) { _pop(null); }
  }
  void _pop(int? value) {
    setState(() => allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) { Navigator.of(context).pop(value); } });
  }
  @override void dispose() { amount.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: widget.commands, builder: (context, _) =>
    PopScope(canPop: allowExit, onPopInvokedWithResult: (didPop, result) { if (!didPop) { _back(); } },
      child: Scaffold(appBar: AppBar(title: const Text('Giảm giá bill'), leading: BackButton(onPressed: _back)),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
          Form(key: form, child: TextFormField(key: const Key('bill-discount-amount'), controller: amount,
            enabled: !widget.commands.blocked, keyboardType: TextInputType.number, maxLength: 13,
            decoration: const InputDecoration(labelText: 'Giảm giá hóa đơn (đ)', counterText: ''),
            validator: (v) { final n = int.tryParse(v?.trim() ?? ''); return n == null || n < 0 || n > 1000000000000 ? 'Nhập số tiền nguyên, không âm.' : null; })),
        ])),
        bottomNavigationBar: Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: FilledButton(
            key: const Key('bill-discount-save'), onPressed: widget.commands.blocked ? null : () {
              if (form.currentState!.validate()) { _pop(int.parse(amount.text.trim())); }
            }, child: const Text('Áp dụng giảm giá'))))))));
}

