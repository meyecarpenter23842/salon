import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/lan/lan_contract.dart';
import '../../core/lan/lan_health_client.dart';
import '../../core/lan/lan_pairing.dart';
import '../../core/lan/lan_read_client.dart';
import '../../core/lan/lan_workflow_client.dart';
import '../../core/lan/lan_workflow_models.dart';
import '../../core/lan/lan_write_contract.dart';
import 'companion_bill_editors.dart';
import 'companion_bills_list.dart';
import 'companion_bill_ui.dart';
import 'companion_catalog_picker.dart';
import 'companion_command_controller.dart';
import 'companion_mobile_list.dart';
import 'companion_workspace.dart' show CompanionPendingNotice;

String _content(LanEditorSnapshot value) => jsonEncode({for (final key in
  ['customerId', 'appointmentId', 'subtotal', 'discountAmount', 'totalAmount', 'lines']) key: value.values[key]});
List<Map<String, dynamic>> _payments(LanEditorSnapshot value) {
  final list = (value.values['payments'] as List? ?? []).map((p) => Map<String, dynamic>.from(p as Map)).toList();
  return list.isEmpty ? [{'method': value.values['paymentMethod'] ?? 'Tiền mặt', 'amount': value.values['totalAmount']}] : list;
}

class CompanionMobileBill extends StatefulWidget {
  const CompanionMobileBill({super.key, required this.connection, required this.readClient, required this.client,
    required this.commands, required this.role, required this.onDenied, this.id, this.appointmentId});
  final LanConnection connection;
  final SalonReadClient readClient;
  final LanWorkflowClient client;
  final CompanionCommandController commands;
  final PhoneWriteRole role;
  final VoidCallback onDenied;
  final String? id, appointmentId;
  @override State<CompanionMobileBill> createState() => _CompanionMobileBillState();
}
class _CompanionMobileBillState extends State<CompanionMobileBill> {
  LanEditorSnapshot? snapshot;
  LanWriteResult? handledResult;
  LanWriteOperation? awaitingOperation;
  Future<void>? receiving;
  List<Map<String, dynamic>>? paymentDraft;
  MobileReadProblem? error;
  String? notice, receiptId;
  bool busy = true, flowBusy = false, needsReload = false, allowExit = false, confirming = false;
  int generation = 0;
  bool get locked => busy || flowBusy || needsReload || widget.commands.blocked || widget.role == PhoneWriteRole.none;
  bool get paymentDirty => paymentDraft != null && snapshot != null && jsonEncode(paymentDraft) != jsonEncode(_payments(snapshot!));
  int get total => snapshot?.values['totalAmount'] as int? ?? 0;
  List<Map<String, dynamic>> get payments => paymentDraft ?? (snapshot == null ? [] : _payments(snapshot!));
  List<Map<String, dynamic>> get lines => (snapshot?.values['lines'] as List? ?? []).map((p) => Map<String, dynamic>.from(p as Map)).toList();
  bool _allows(LanWriteOperation op) => op.allows(widget.role);
  @override void initState() { super.initState(); widget.commands.addListener(_changed); _initialize(); }
  void _changed() {
    if (!mounted) { return; }
    if (awaitingOperation != null && !widget.commands.busy && widget.commands.pending == null) {
      final result = widget.commands.lastResult;
      if (result != null && widget.commands.lastOperation == awaitingOperation) { _receive(result); }
      else { needsReload = true; }
    }
    setState(() {});
  }
  Future<void> _initialize() async {
    if (widget.id != null) {
      if (widget.commands.pending?.targetId == widget.id) { awaitingOperation = widget.commands.pending!.operation; }
      await _load(widget.id!); return;
    }
    final current = ++generation;
    try {
      final editor = await widget.client.editor(widget.connection, widget.commands.token,
        widget.appointmentId == null ? 'customer' : 'appointment', widget.appointmentId);
      if (!mounted || current != generation) { return; }
      setState(() { snapshot = editor; busy = false; });
      await _run(widget.appointmentId == null ? LanWriteOperation.sessionCreate : LanWriteOperation.sessionOpenAppointment, {});
    } catch(e) { _readFailed(e, current); }
  }
  void _readFailed(Object e, int current) {
    if (!mounted || current != generation) { return; }
    setState(() {
      busy = false;
      error = e is PairingFailure && e.code == LanErrorCode.alreadyPaid
        ? const MobileReadProblem(Icons.check_circle_outline, 'Bill đã thanh toán',
          'Về danh sách Đã thanh toán để xem hóa đơn trên máy salon.')
        : MobileReadProblem.from(e);
    });
    if (e is PairingFailure && [LanErrorCode.forbidden, LanErrorCode.unauthenticated].contains(e.code)) { widget.onDenied(); }
  }
  Future<void> _load(String id) async {
    final current = ++generation;
    setState(() { busy = true; error = null; });
    try {
      final value = await widget.client.editor(widget.connection, widget.commands.token, 'session', id);
      if (!mounted || current != generation) { return; }
      setState(() { snapshot = value; busy = false; needsReload = false; });
    } catch(e) { _readFailed(e, current); }
  }
  Future<void> _receive(LanWriteResult result) {
    if (identical(result, handledResult)) { return receiving ?? Future.value(); }
    handledResult = result; awaitingOperation = null;
    if (result.type == 'invoice') {
      setState(() { receiptId = result.id; paymentDraft = null; allowExit = true; });
      return Future.value();
    }
    if (result.type == 'session') {
      receiving = _load(result.id); return receiving!;
    }
    return Future.value();
  }
  Future<LanWriteResult?> _run(LanWriteOperation op, Map<String, dynamic> payload) async {
    final value = snapshot;
    if (value == null || busy || needsReload || widget.commands.blocked || !_allows(op)) { return null; }
    setState(() { awaitingOperation = op; notice = null; });
    final result = await widget.commands.submit(op, value, payload);
    if (!mounted) { return result; }
    if (result != null) { await _receive(result); }
    else if (widget.commands.pending == null) {
      setState(() { needsReload = true; });
    }
    if ([LanErrorCode.forbidden, LanErrorCode.unauthenticated].contains(widget.commands.failureCode)) { widget.onDenied(); }
    return result;
  }
  Future<void> _back() async {
    if (confirming || widget.commands.busy || flowBusy) { return; } confirming = true;
    final pending = widget.commands.pending != null;
    final leave = !paymentDirty && !pending || await confirmBillDiscard(context, pending: pending);
    confirming = false;
    if (mounted && leave) {
      setState(() => allowExit = true);
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) { Navigator.of(context).pop(true); } });
    }
  }
  Future<void> _reload() async {
    if (busy || flowBusy || widget.commands.blocked || snapshot?.kind != 'session') { return; }
    if (paymentDirty && !await confirmBillDiscard(context) || !mounted) { return; }
    paymentDraft = null; notice = null; await _load(snapshot!.id!);
  }
  Future<void> _pick(String kind) async {
    if (locked || snapshot?.kind != 'session') { return; }
    final selected = await Navigator.of(context).push<Map<String, String>>(MaterialPageRoute(builder: (_) =>
      CompanionCatalogPicker(connection: widget.connection, token: widget.commands.token, client: widget.client,
        kind: kind, epoch: snapshot!.epoch, onDenied: widget.onDenied)));
    if (!mounted || selected == null || selected.isEmpty || locked) { return; }
    await _run(kind == 'customers' ? LanWriteOperation.sessionSelectCustomer :
      kind == 'services' ? LanWriteOperation.sessionAddService : LanWriteOperation.sessionAddProduct,
      kind == 'customers' ? {'customerId': selected.keys.first} : kind == 'services'
        ? {'serviceId': selected.keys.first, 'employeeId': null} : {'productId': selected.keys.first});
  }
  Future<void> _editLine(Map<String, dynamic> line) async {
    if (locked) { return; }
    await Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) =>
      CompanionBillLineEditor(snapshot: snapshot!, line: line, connection: widget.connection, client: widget.client,
        commands: widget.commands, role: widget.role, onDenied: widget.onDenied)));
    if (mounted && !widget.commands.blocked) { await _load(snapshot!.id!); }
  }
  Future<void> _remove(Map<String, dynamic> line) async {
    if (locked) { return; }
    final yes = await showDialog<bool>(context: context, useRootNavigator: false, builder: (context) => AlertDialog(
      title: const Text('Xóa dòng khỏi bill?'), content: Text(line['title'] as String),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Giữ lại')),
        FilledButton(key: const Key('bill-remove-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Xóa dòng'))]));
    if (mounted && yes == true) { await _run(LanWriteOperation.sessionRemoveLine, {'lineId': line['id']}); }
  }
  Future<void> _discount() async {
    if (locked || !_allows(LanWriteOperation.sessionDiscount)) { return; }
    final amount = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) =>
      CompanionBillAmountEditor(amount: snapshot!.values['discountAmount'] as int, commands: widget.commands)));
    if (mounted && amount != null) { await _run(LanWriteOperation.sessionDiscount, {'amount': amount}); }
  }
  Future<void> _payment() async {
    if (locked || !_allows(LanWriteOperation.sessionPayment)) { return; }
    final next = await Navigator.of(context).push<List<Map<String, dynamic>>>(MaterialPageRoute(builder: (_) =>
      CompanionBillPaymentEditor(total: total, payments: payments, commands: widget.commands)));
    if (mounted && next != null) { setState(() { paymentDraft = next; notice = null; }); }
  }
  Future<void> _checkout() async {
    if (locked || !_allows(LanWriteOperation.sessionCheckout) || snapshot?.kind != 'session') { return; }
    if ((snapshot!.values['customerId']?.toString() ?? '').isEmpty || lines.isEmpty) { return; }
    final allocations = payments.map((p) => Map<String, dynamic>.from(p)).toList();
    if (allocations.fold<int>(0, (sum, p) => sum + (p['amount'] as int)) != total) {
      setState(() => notice = 'Tổng bill đã đổi. Kiểm tra lại khoản thanh toán trước khi xác nhận.'); return;
    }
    final reviewedContent = _content(snapshot!);
    final confirmed = await showDialog<bool>(context: context, useRootNavigator: false, builder: (context) => AlertDialog(
      title: const Text('Xác nhận thanh toán'),
      content: SizedBox(width: double.maxFinite, child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .55),
        child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(snapshot!.values['customerLabel'] as String, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final line in lines) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(
            '${line['title']} · ${line['quantity']} × ${billMoney(line['unitPrice'] as int)} = ${billMoney(line['totalPrice'] as int)}'
            '${line['isService'] == true ? '\nNhân viên: ${(line['employeeLabel']?.toString() ?? '').isEmpty ? 'Chưa gán' : line['employeeLabel']}' : ''}')),
          const Divider(),
          billAmountRow('Tạm tính', billMoney(snapshot!.values['subtotal'] as int)),
          billAmountRow('Giảm giá', billMoney(snapshot!.values['discountAmount'] as int)),
          billAmountRow('Tổng thanh toán', billMoney(total), strong: true),
          for (final p in allocations) billAmountRow(p['method'] as String, billMoney(p['amount'] as int)),
          if (lines.any((line) => line['stockOnHand'] is int && (line['stockOnHand'] as int) - (line['quantity'] as int) < 0))
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('Có sản phẩm dự kiến âm kho sau thanh toán. Vẫn được bán.',
              style: TextStyle(color: Colors.red))),
        ])))),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Kiểm tra lại')),
        FilledButton(key: const Key('bill-confirm-checkout'), onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận thanh toán'))]));
    if (!mounted || confirmed != true || locked) { return; }
    setState(() => flowBusy = true);
    try {
      if (jsonEncode(allocations) != jsonEncode(_payments(snapshot!))) {
        final saved = await _run(LanWriteOperation.sessionPayment, {'payments': allocations});
        if (!mounted || saved == null || error != null || snapshot?.kind != 'session') { return; }
        if (_content(snapshot!) != reviewedContent || jsonEncode(_payments(snapshot!)) != jsonEncode(allocations)) {
          setState(() => notice = 'Bill đã đổi trên máy salon. Kiểm tra tổng tiền và xác nhận lại trước khi thanh toán.'); return;
        }
      }
      await _run(LanWriteOperation.sessionCheckout, {});
    } finally { if (mounted) { setState(() => flowBusy = false); } }
  }
  @override void dispose() { generation++; widget.commands.removeListener(_changed); super.dispose(); }
  @override Widget build(BuildContext context) {
    if (receiptId != null) {
      return CompanionReceipt(connection: widget.connection, token: widget.commands.token, client: widget.readClient,
        id: receiptId!, onDenied: widget.onDenied, success: true);
    }
    final value = snapshot;
    return PopScope(canPop: allowExit, onPopInvokedWithResult: (didPop, result) { if (!didPop) { _back(); } },
      child: Scaffold(appBar: AppBar(title: const Text('Bill đang làm'), leading: BackButton(onPressed: _back),
        actions: [IconButton(key: const Key('bill-reload'), onPressed: busy || flowBusy || widget.commands.blocked ? null : _reload,
          tooltip: 'Tải lại bill', icon: const Icon(Icons.refresh))]),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
          if (widget.commands.pending != null || widget.commands.message != null) ...[
            if (widget.commands.pending?.operation == LanWriteOperation.sessionCheckout)
              const Text('Kết quả thanh toán chưa rõ. Kiểm tra kết quả trước khi thu tiền hoặc thanh toán lại.'),
            if (widget.commands.pending?.operation == LanWriteOperation.sessionPayment)
              const Text('Khoản thanh toán đang chờ kiểm tra; bill chưa được xác nhận checkout trong luồng này.'),
            CompanionPendingNotice(commands: widget.commands),
          ],
          if (needsReload) const Padding(padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Cần tải lại bill và kiểm tra dữ liệu trước khi thao tác tiếp.')),
          if (notice != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(notice!, key: const Key('bill-notice'))),
          if (busy || flowBusy) const LinearProgressIndicator(),
          if (error != null) MobileStatus(icon: error!.icon, title: error!.title, message: error!.message,
            action: 'Thử lại', onAction: widget.commands.blocked ? () {} : () => value?.kind == 'session' ? _load(value!.id!) : _initialize())
          else if (value?.kind == 'session') ...[
            billGroup(context, 'Khách hàng', [
              Text(value!.values['customerLabel'] as String, style: Theme.of(context).textTheme.titleLarge),
              if (_allows(LanWriteOperation.sessionSelectCustomer)) OutlinedButton.icon(key: const Key('bill-select-customer'),
                onPressed: locked ? null : () => _pick('customers'), icon: const Icon(Icons.person_outline), label: const Text('Chọn hoặc đổi khách')),
              if ((value.values['customerId']?.toString() ?? '').isEmpty) const Text('Chọn khách hàng trước khi thanh toán.'),
            ]),
            billGroup(context, 'Dịch vụ và sản phẩm', [
              if (_allows(LanWriteOperation.sessionAddService)) Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(key: const Key('bill-add-service'), onPressed: locked ? null : () => _pick('services'),
                  icon: const Icon(Icons.add), label: const Text('Dịch vụ')),
                OutlinedButton.icon(key: const Key('bill-add-product'), onPressed: locked ? null : () => _pick('products'),
                  icon: const Icon(Icons.add), label: const Text('Sản phẩm')),
              ]),
              if (lines.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Thêm dịch vụ hoặc sản phẩm vào bill.')),
              for (final line in lines) Padding(padding: const EdgeInsets.only(top: 16), child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(line['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  billAmountRow('${line['quantity']} × ${billMoney(line['unitPrice'] as int)}', billMoney(line['totalPrice'] as int)),
                  if ((line['discountAmount'] as int? ?? 0) > 0) Text('Giảm dòng: ${billMoney(line['discountAmount'] as int)}'),
                  if (line['isService'] == true) Text('Nhân viên: ${(line['employeeLabel']?.toString() ?? '').isEmpty ? 'Chưa gán' : line['employeeLabel']}'),
                  if (line['stockOnHand'] is int && ((line['stockOnHand'] as int) < 0 || (line['stockOnHand'] as int) - (line['quantity'] as int) < 0))
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(
                      'Tồn ${line['stockOnHand']} · Dự kiến sau thanh toán ${(line['stockOnHand'] as int) - (line['quantity'] as int)} · Vẫn được bán',
                      key: ValueKey('bill-stock-${line['id']}'), style: const TextStyle(color: Colors.red))),
                  if (_allows(LanWriteOperation.sessionUpdateLine)) Wrap(spacing: 8, children: [
                    TextButton.icon(key: ValueKey('bill-edit-${line['id']}'), onPressed: locked ? null : () => _editLine(line),
                      icon: const Icon(Icons.edit_outlined), label: const Text('Chỉnh dòng')),
                    TextButton.icon(key: ValueKey('bill-remove-${line['id']}'), onPressed: locked ? null : () => _remove(line),
                      icon: const Icon(Icons.delete_outline), label: const Text('Xóa')),
                  ]),
                  const Divider(),
                ])),
            ]),
            billGroup(context, 'Tổng tiền', [
              billAmountRow('Tạm tính', billMoney(value.values['subtotal'] as int)),
              billAmountRow('Giảm giá bill', billMoney(value.values['discountAmount'] as int)),
              if (_allows(LanWriteOperation.sessionDiscount)) TextButton(key: const Key('bill-edit-discount'),
                onPressed: locked ? null : _discount, child: const Text('Chỉnh giảm giá')),
            ]),
            billGroup(context, 'Khoản thanh toán', [
              for (final p in payments) billAmountRow(p['method'] as String, billMoney(p['amount'] as int)),
              if (paymentDirty) const Text('Khoản thanh toán đã chọn chưa lưu; sẽ lưu khi bạn xác nhận thanh toán.'),
              if (_allows(LanWriteOperation.sessionPayment)) OutlinedButton.icon(key: const Key('bill-edit-payment'),
                onPressed: locked ? null : _payment, icon: const Icon(Icons.payments_outlined), label: const Text('Chọn phương thức / chia khoản')),
              if (!_allows(LanWriteOperation.sessionCheckout)) const Text('Chủ salon cần cấp quyền Thu ngân để thanh toán.'),
            ]),
          ],
        ])),
        bottomNavigationBar: value?.kind != 'session' || error != null ? null : SafeArea(child: Padding(
          padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            billAmountRow('Tổng thanh toán', billMoney(total), strong: true),
            if (_allows(LanWriteOperation.sessionCheckout)) FilledButton(key: const Key('bill-checkout'),
              onPressed: locked || lines.isEmpty || (value!.values['customerId']?.toString() ?? '').isEmpty ? null : _checkout,
              child: const Text('Kiểm tra và thanh toán')),
          ])))));
  }
}
