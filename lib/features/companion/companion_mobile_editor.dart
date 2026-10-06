import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/lan/lan_contract.dart';
import '../../core/lan/lan_health_client.dart';
import '../../core/lan/lan_pairing.dart';
import '../../core/lan/lan_read_models.dart';
import '../../core/lan/lan_workflow_client.dart';
import '../../core/lan/lan_workflow_models.dart';
import '../../core/lan/lan_write_contract.dart';
import 'companion_catalog_picker.dart';
import 'companion_command_controller.dart';
import 'companion_mobile_list.dart';
import 'companion_workspace.dart' show CompanionPendingNotice;

class CompanionMobileEditor extends StatefulWidget {
  const CompanionMobileEditor({super.key, required this.connection, required this.client,
    required this.commands, required this.role, required this.onDenied, required this.kind, this.id});
  final LanConnection connection;
  final LanWorkflowClient client;
  final CompanionCommandController commands;
  final PhoneWriteRole role;
  final VoidCallback onDenied;
  final String kind;
  final String? id;
  @override State<CompanionMobileEditor> createState() => _CompanionMobileEditorState();
}
class _CompanionMobileEditorState extends State<CompanionMobileEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  LanEditorSnapshot? snapshot;
  MobileReadProblem? error;
  String original = '';
  String tier = 'Standard', status = 'Đã đặt';
  Map<String, String> customer = {}, employee = {}, services = {};
  DateTime? day;
  TimeOfDay? time;
  bool busy = true, allowExit = false, confirming = false, attempted = false;
  bool submitted = false, completing = false, awaitingOutcome = false, needsReload = false;
  int generation = 0;
  bool get appointment => widget.kind == 'appointment';
  int observedGeneration = 0;
  bool get locked => widget.commands.blocked || widget.role == PhoneWriteRole.none || busy;
  bool get dirty => snapshot != null && jsonEncode(_payload()) != original;
  @override void initState() { super.initState(); observedGeneration = widget.commands.dataGeneration; widget.commands.addListener(_changed); _load(); }
  void _changed() {
    if (!mounted) { return; }
    if (observedGeneration != widget.commands.dataGeneration) {
      observedGeneration = widget.commands.dataGeneration; needsReload = true;
    }
    if (submitted && widget.commands.pending != null) { awaitingOutcome = true; }
    if (submitted && awaitingOutcome && widget.commands.pending == null && !widget.commands.busy) {
      awaitingOutcome = false;
      if (widget.commands.lastResult != null) { _finish(); return; }
      // A rejected/discarded command cannot reuse its old snapshot after recovery.
      needsReload = true;
    }
    setState(() {});
  }
  void _finish() {
    if (!mounted || completing) { return; }
    completing = true;
    setState(() { allowExit = true; original = jsonEncode(_payload()); });
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) { Navigator.of(context).pop(true); } });
  }
  TextEditingController _field(String name) => fields.putIfAbsent(name, TextEditingController.new);
  String _text(String name) => _field(name).text.trim();
  Map<String, dynamic> _payload() => appointment ? {
    'customerId': customer.keys.firstOrNull ?? '', 'serviceIds': services.keys.toList(),
    'employeeId': employee.keys.firstOrNull ?? '', 'day': day == null ? '' : salonDay(day!),
    'time': time == null ? '' : '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}',
    'status': status, 'durationMinutes': int.tryParse(_text('durationMinutes')) ?? 0,
    'slotLabel': _text('slotLabel'), 'note': _text('note'),
  } : {for(final key in ['fullName', 'phone', 'email', 'favoriteService', 'hairProfile', 'note']) key: _text(key), 'tier': tier};

  Future<bool> _confirm() async {
    if (!dirty) { return true; }
    final pending = widget.commands.pending != null;
    return await showDialog<bool>(context: context, useRootNavigator: false, builder: (context) => AlertDialog(
      title: Text(pending ? 'Quay lại khi yêu cầu đang chờ?' : 'Bỏ thay đổi chưa lưu?'),
      content: Text(pending ? 'Kết quả lưu vẫn chưa rõ. Yêu cầu được giữ trên điện thoại để đối chiếu với máy salon, kể cả khi bạn quay lại.' : 'Thông tin đã nhập chưa được lưu trên máy salon.'),
      actions: [
        TextButton(key: const Key('mobile-keep-editing'), onPressed: () => Navigator.pop(context, false), child: Text(pending ? 'Ở lại kiểm tra' : 'Tiếp tục sửa')),
        FilledButton(key: const Key('mobile-discard'), onPressed: () => Navigator.pop(context, true), child: Text(pending ? 'Quay lại' : 'Bỏ thay đổi')),
      ])) ?? false;
  }
  Future<void> _back() async {
    if (confirming || widget.commands.busy) { return; }
    confirming = true;
    final leave = await _confirm();
    confirming = false;
    if (mounted && leave) {
      setState(() => allowExit = true);
      // PopScope must be rebuilt before a programmatic pop.
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) { Navigator.of(context).pop(false); } });
    }
  }
  Future<void> _reload() async {
    if (locked || !await _confirm() || !mounted) { return; }
    await _load();
  }
  Future<void> _load() async {
    final current = ++generation;
    setState(() { busy = true; error = null; });
    try {
      final next = await widget.client.editor(widget.connection, widget.commands.token, widget.kind, widget.id);
      if (!mounted || generation != current) { return; }
      final values = next.values;
      if (appointment) {
        day = DateTime.tryParse(values['day']?.toString() ?? '');
        final parts = (values['time']?.toString() ?? '').split(':');
        time = parts.length == 2 && int.tryParse(parts[0]) != null && int.tryParse(parts[1]) != null
          ? TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])) : null;
        status = values['status']?.toString() ?? 'Đã đặt';
        customer = (values['customerId']?.toString() ?? '').isEmpty ? {} : {values['customerId'].toString(): values['customerLabel']?.toString() ?? 'Khách hàng đã chọn'};
        employee = (values['employeeId']?.toString() ?? '').isEmpty ? {} : {values['employeeId'].toString(): values['employeeLabel']?.toString() ?? 'Nhân viên đã chọn'};
        final labels = Map<String, dynamic>.from(values['serviceLabels'] as Map? ?? {});
        services = {for(final id in (values['serviceIds'] as List? ?? []).cast<String>()) id: labels[id]?.toString() ?? 'Dịch vụ đã chọn'};
        for(final name in ['durationMinutes', 'slotLabel', 'note']) { _field(name).text = values[name]?.toString() ?? ''; }
      } else {
        tier = values['tier']?.toString() ?? 'Standard';
        for(final name in ['fullName', 'phone', 'email', 'favoriteService', 'hairProfile', 'note']) { _field(name).text = values[name]?.toString() ?? ''; }
      }
      setState(() { snapshot = next; original = jsonEncode(_payload()); busy = false; attempted = false; needsReload = false; submitted = false; awaitingOutcome = false; });
    } catch(e) {
      if (!mounted || generation != current) { return; }
      setState(() { busy = false; error = MobileReadProblem.from(e); });
      if (e is PairingFailure && [LanErrorCode.forbidden, LanErrorCode.unauthenticated].contains(e.code)) { widget.onDenied(); }
    }
  }
  Future<void> _pick(String kind) async {
    if (locked || snapshot == null) { return; }
    final selected = await Navigator.of(context).push<Map<String, String>>(MaterialPageRoute(builder: (_) =>
      CompanionCatalogPicker(connection: widget.connection, token: widget.commands.token, client: widget.client,
        kind: kind, epoch: snapshot!.epoch, onDenied: widget.onDenied, multiple: kind == 'services',
        selected: kind == 'services' ? services : kind == 'customers' ? customer : employee)));
    if (!mounted || selected == null) { return; }
    setState(() { if (kind == 'customers') { customer = selected; } else if(kind == 'employees') { employee = selected; } else { services = selected; } });
  }
  Future<void> _pickDay() async {
    final selected = await showDatePicker(context: context, useRootNavigator: false, initialDate: day ?? DateTime.now(),
      firstDate: DateTime(2000), lastDate: DateTime(2100), helpText: 'Chọn ngày tại salon');
    if (mounted && selected != null) { setState(() => day = selected); }
  }
  Future<void> _pickTime() async {
    final selected = await showTimePicker(context: context, useRootNavigator: false, initialTime: time ?? const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Chọn giờ tại salon', builder: (context, child) =>
        MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!));
    if (mounted && selected != null) { setState(() => time = selected); }
  }
  Future<void> _save() async {
    if (locked || needsReload || snapshot == null) { return; }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => attempted = true);
    if (!form.currentState!.validate() || (appointment && (customer.isEmpty || employee.isEmpty || services.isEmpty || day == null || time == null))) { return; }
    final operation = appointment
      ? widget.id == null ? LanWriteOperation.appointmentCreate : LanWriteOperation.appointmentUpdate
      : widget.id == null ? LanWriteOperation.customerCreate : LanWriteOperation.customerUpdate;
    if (!operation.allows(widget.role)) { return; }
    submitted = true;
    final result = await widget.commands.submit(operation, snapshot!, _payload());
    if (!mounted || result == null) { return; }
    _finish();
  }
  Widget _input(String name, String label, int max, {bool required = false, TextInputType? keyboard, int lines = 1, String? Function(String)? validate}) =>
    Padding(padding: const EdgeInsets.only(bottom: 16), child: TextFormField(key: Key('mobile-field-$name'),
      controller: _field(name), enabled: !locked, keyboardType: keyboard, minLines: lines, maxLines: lines,
      maxLength: max, textInputAction: lines > 1 ? TextInputAction.newline : TextInputAction.next,
      decoration: InputDecoration(labelText: required ? '$label *' : label, counterText: '', alignLabelWithHint: lines > 1),
      onChanged: (_) => setState(() {}),
      validator: (value) { final text = (value ?? '').trim(); if (required && text.isEmpty) { return 'Vui lòng nhập $label.'; }
        if (text.length > max) { return 'Tối đa $max ký tự.'; } return validate?.call(text); }));
  Widget _section(String title, List<Widget> children) => Card(child: Padding(padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 16), ...children,
    ])));
  Widget _selector(String kind, String label, Map<String, String> selection) => Padding(padding: const EdgeInsets.only(bottom: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OutlinedButton(key: Key('mobile-select-$kind'), onPressed: locked ? null : () => _pick(kind),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(selection.isEmpty ? '$label *' : selection.values.join(' + '), textAlign: TextAlign.center))),
      if (attempted && selection.isEmpty) Padding(padding: const EdgeInsets.only(top: 6),
        child: Text('Vui lòng chọn $label.', style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ]));
  List<Widget> _customerFields() => [
    _section('Thông tin liên hệ', [
      _input('fullName', 'Họ tên', 120, required: true, keyboard: TextInputType.name),
      _input('phone', 'Số điện thoại', 24, required: true, keyboard: TextInputType.phone, validate: (text) =>
        !RegExp(r'^[+0-9 ()-]+$').hasMatch(text) || text.replaceAll(RegExp(r'\D'), '').length < 6 ? 'Nhập số điện thoại hợp lệ (ít nhất 6 chữ số).' : null),
      _input('email', 'Email', 120, keyboard: TextInputType.emailAddress, validate: (text) =>
        text.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text) ? 'Email chưa đúng định dạng.' : null),
    ]),
    _section('Chăm sóc khách hàng', [
      DropdownButtonFormField<String>(key: const Key('mobile-customer-tier'), initialValue: tier, isExpanded: true,
        decoration: const InputDecoration(labelText: 'Hạng khách'),
        items: {...['Standard', 'Member', 'VIP'], tier}.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: locked ? null : (value) => setState(() => tier = value!)),
      const SizedBox(height: 16),
      _input('favoriteService', 'Dịch vụ yêu thích', 200),
      _input('hairProfile', 'Hồ sơ tóc', 2000, lines: 3),
      _input('note', 'Ghi chú', 2000, lines: 3),
    ]),
  ];
  List<Widget> _appointmentFields() => [
    _section('Khách hàng và dịch vụ', [
      _selector('customers', 'khách hàng', customer),
      _selector('services', 'dịch vụ', services),
      _selector('employees', 'nhân viên', employee),
    ]),
    _section('Thời gian tại salon', [
      const Text('Ngày và giờ theo máy salon.'),
      const SizedBox(height: 12),
      OutlinedButton.icon(key: const Key('mobile-appointment-day'), onPressed: locked ? null : _pickDay,
        icon: const Icon(Icons.calendar_month), label: Text(day == null ? 'Chọn ngày *' : DateFormat('dd/MM/yyyy').format(day!))),
      const SizedBox(height: 8),
      OutlinedButton.icon(key: const Key('mobile-appointment-time'), onPressed: locked ? null : _pickTime,
        icon: const Icon(Icons.schedule), label: Text(time == null ? 'Chọn giờ *' : '${time!.hour.toString().padLeft(2,'0')}:${time!.minute.toString().padLeft(2,'0')}')),
      if (attempted && (day == null || time == null)) Text('Vui lòng chọn ngày và giờ.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 16),
      _input('durationMinutes', 'Thời lượng dự kiến (phút)', 4, required: true, keyboard: TextInputType.number, validate: (text) {
        final value = int.tryParse(text); return value == null || value < 5 || value > 1440 ? 'Nhập từ 5 đến 1440 phút.' : null;
      }),
      const Text('Máy salon tính thời lượng thực tế theo dịch vụ đã chọn.'),
    ]),
    _section('Trạng thái và ghi chú', [
      DropdownButtonFormField<String>(key: const Key('mobile-appointment-status'), initialValue: status, isExpanded: true,
        decoration: const InputDecoration(labelText: 'Trạng thái'),
        items: {...['Chờ xác nhận', 'Đã đặt', 'Đã đến', 'Đang làm', 'Hoàn thành', 'Đã hủy', 'Đã xác nhận'], status}
          .map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: locked ? null : (value) => setState(() => status = value!)),
      const SizedBox(height: 16), _input('slotLabel', 'Nhãn khung giờ', 40), _input('note', 'Ghi chú', 2000, lines: 3),
    ]),
  ];
  @override void dispose() {
    generation++; widget.commands.removeListener(_changed);
    for(final field in fields.values) { field.dispose(); }
    super.dispose();
  }
  @override Widget build(BuildContext context) => PopScope<bool>(
    canPop: allowExit || (!dirty && !widget.commands.busy),
    onPopInvokedWithResult: (didPop, result) { if (!didPop) { _back(); } },
    child: Scaffold(
      appBar: AppBar(title: Text(appointment ? widget.id == null ? 'Đặt lịch hẹn' : 'Sửa lịch hẹn'
          : widget.id == null ? 'Thêm khách hàng' : 'Sửa khách hàng'),
        actions: [IconButton(key: const Key('mobile-reload-editor'), tooltip: 'Tải lại từ máy salon', onPressed: locked ? null : _reload, icon: const Icon(Icons.refresh))]),
      body: SafeArea(child: busy ? const Center(child: CircularProgressIndicator())
        : error != null ? MobileStatus(icon: error!.icon, title: error!.title,
          message: error!.message, action: 'Thử lại', onAction: _load)
        : Form(key: form, child: ListView(key: const Key('mobile-editor-scroll'), padding: const EdgeInsets.all(12), children: [
          if (widget.commands.message != null || widget.commands.pending != null) CompanionPendingNotice(commands: widget.commands),
          if (needsReload) const Padding(padding: EdgeInsets.all(12), child: Text('Tải lại biểu mẫu trước khi lưu tiếp. Nội dung đang nhập vẫn được giữ để bạn kiểm tra.')),
          if (widget.commands.pending != null) const Padding(padding: EdgeInsets.all(12),
            child: Text('Bạn có thể quay lại; thao tác chờ vẫn được giữ để đối chiếu trên máy salon.')),
          ...(appointment ? _appointmentFields() : _customerFields()),
        ]))),
      bottomNavigationBar: snapshot == null || error != null ? null : Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), child: SafeArea(child: Padding(padding: const EdgeInsets.all(16),
        child: FilledButton.icon(key: const Key('mobile-save'), onPressed: locked || needsReload ? null : _save,
          icon: const Icon(Icons.check), label: Text(widget.commands.busy ? 'Đang lưu…' : 'Lưu trên máy salon'))))),
    ));
}

