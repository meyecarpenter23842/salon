import 'package:flutter/material.dart';
import '../../core/lan/lan_contract.dart';
import '../../core/lan/lan_health_client.dart';
import '../../core/lan/lan_pairing.dart';
import '../../core/lan/lan_read_client.dart';
import '../../core/lan/lan_workflow_client.dart';
import '../../core/lan/lan_workflow_models.dart';
import '../../core/lan/lan_write_contract.dart';
import 'companion_command_controller.dart';
import 'companion_data_panel.dart';

const _statuses = ['Chờ xác nhận', 'Đã đặt', 'Đã đến', 'Đang làm', 'Hoàn thành', 'Đã hủy', 'Đã xác nhận'];
const _methods = ['Tiền mặt', 'Chuyển khoản', 'Thẻ'];

class CompanionWorkspace extends StatefulWidget {
  const CompanionWorkspace({super.key, required this.connection, required this.readClient,
    required this.client, required this.commands, required this.role, required this.onDenied});
  final LanConnection connection;
  final SalonReadClient readClient;
  final LanWorkflowClient client;
  final CompanionCommandController commands;
  final PhoneWriteRole role;
  final VoidCallback onDenied;
  @override
  State<CompanionWorkspace> createState() => _CompanionWorkspaceState();
}

class _CompanionWorkspaceState extends State<CompanionWorkspace> {
  LanEditorSnapshot? _editor;
  final Map<String, TextEditingController> _fields = {};
  Map<String, dynamic> _values = {};
  String? _picker;
  String? _pickerField;
  String? _pickerLine;
  LanCatalogPage? _catalog;
  final _search = TextEditingController();
  String _query = '';
  int _offset = 0;
  bool _sessions = false;
  bool _busy = false;
  bool _confirmCheckout = false;
  String? _error;
  int _generation = 0;
  int _readVersion = 0;

  bool allows(LanWriteOperation op) => op.allows(widget.role);
  bool get _locked => _busy || widget.commands.blocked;
  @override
  void initState() { super.initState(); widget.commands.addListener(_changed); }
  void _changed() { if (mounted) setState(() {}); }
  void _clearFields() { for (final field in _fields.values) { field.dispose(); } _fields.clear(); }
  void _setEditor(LanEditorSnapshot value) {
    _clearFields(); _values = Map<String, dynamic>.from(value.values); _editor = value;
    _picker = null; _catalog = null; _sessions = false; _confirmCheckout = false; _error = null;
    if (value.kind == 'customer') {
      for (final key in ['fullName', 'phone', 'email', 'tier', 'favoriteService', 'hairProfile', 'note']) {
        _fields[key] = TextEditingController(text: _values[key]?.toString() ?? '');
      }
    } else if (value.kind == 'appointment') {
      for (final key in ['day', 'time', 'durationMinutes', 'slotLabel', 'note']) {
        _fields[key] = TextEditingController(text: _values[key]?.toString() ?? '');
      }
      _values['serviceIds'] = List<String>.from(_values['serviceIds'] as List);
      _values['serviceLabels'] = Map<String, dynamic>.from((_values['serviceLabels'] as Map?) ?? {});
    } else {
      _fields['discount'] = TextEditingController(text: '${_values['discountAmount']}');
      final payments = _values['payments'] as List;
      for (final method in _methods) {
        final allocations = payments.where((p) => p['method'] == method);
        _fields['payment-$method'] = TextEditingController(text: allocations.isEmpty ? '0' : '${allocations.first['amount']}');
      }
      for (final line in _values['lines'] as List) {
        _fields['price-${line['id']}'] = TextEditingController(text: '${line['unitPrice']}');
      }
    }
  }

  Future<void> _edit(String kind, String? id) async {
    if (_locked) return;
    final generation = ++_generation;
    setState(() { _busy = true; _error = null; });
    try {
      final value = await widget.client.editor(widget.connection, widget.commands.token, kind, id);
      if (mounted && generation == _generation) setState(() => _setEditor(value));
    } catch (error) { _failed(error, generation); }
    finally { if (mounted && generation == _generation) setState(() => _busy = false); }
  }
  void _failed(Object error, int generation) {
    if (!mounted || generation != _generation) return;
    setState(() => _error = 'Chưa tải được dữ liệu. Kiểm tra kết nối rồi thử lại.');
    if (error is PairingFailure &&
        [LanErrorCode.forbidden, LanErrorCode.unauthenticated].contains(error.code)) widget.onDenied();
  }

  Future<void> _pick(String kind, String field, {String? lineId}) async {
    if (_locked) return;
    _search.clear(); _query = '';
    setState(() { _picker = kind; _pickerField = field; _pickerLine = lineId; _catalog = null; });
    await _loadCatalog();
  }
  Future<void> _loadCatalog({int offset = 0}) async {
    final kind = _picker;
    if (kind == null || _locked) return;
    final generation = ++_generation;
    setState(() { _busy = true; _error = null; _catalog = null; });
    try {
      final page = await widget.client.catalog(widget.connection, widget.commands.token, kind, _query, offset);
      if (mounted && generation == _generation) setState(() { _catalog = page; _offset = offset; });
    } catch (error) { _failed(error, generation); }
    finally { if (mounted && generation == _generation) setState(() => _busy = false); }
  }
  Future<void> _bills() async {
    if (_locked) return;
    _clearFields();
    setState(() { _editor = null; _sessions = true; _picker = 'sessions'; _pickerField = null;
      _catalog = null; _query = ''; _search.clear(); _confirmCheckout = false; });
    await _loadCatalog();
  }
  Future<void> _selected(LanCatalogItem item) async {
    if (_locked) return;
    if (_sessions) { await _edit('session', item.id); return; }
    final field = _pickerField;
    if (field == 'serviceIds') {
      setState(() {
        final ids = _values['serviceIds'] as List<String>;
        final labels = _values['serviceLabels'] as Map<String, dynamic>;
        if (ids.contains(item.id)) { ids.remove(item.id); labels.remove(item.id); }
        else if (ids.length < 20) { ids.add(item.id); labels[item.id] = item.title; }
      });
      return;
    }
    if (field == 'customerId' || field == 'employeeId') {
      setState(() { _values[field!] = item.id;
        _values[field == 'customerId' ? 'customerLabel' : 'employeeLabel'] = item.title;
        _picker = null; _catalog = null; });
      return;
    }
    final operation = field == 'billCustomer' ? LanWriteOperation.sessionSelectCustomer :
      field == 'billService' ? LanWriteOperation.sessionAddService :
      field == 'billProduct' ? LanWriteOperation.sessionAddProduct : LanWriteOperation.sessionAssignEmployee;
    final payload = field == 'billCustomer' ? <String, dynamic>{'customerId': item.id} :
      field == 'billService' ? <String, dynamic>{'serviceId': item.id, 'employeeId': null} :
      field == 'billProduct' ? <String, dynamic>{'productId': item.id} :
      <String, dynamic>{'lineId': _pickerLine, 'employeeId': item.id};
    await _submit(operation, payload);
  }

  Future<void> _submit(LanWriteOperation op, Map<String, dynamic> payload, {LanEditorSnapshot? snapshot}) async {
    if (_locked || !allows(op)) return;
    final value = snapshot ?? _editor;
    if (value == null) return;
    setState(() { _error = null; _confirmCheckout = false; });
    final result = await widget.commands.submit(op, value, payload);
    if (!mounted) return;
    if (result != null) {
      if (result.type == 'session') await _edit('session', result.id);
      else { _clearFields(); setState(() { _editor = null; _picker = null; _sessions = false; _readVersion++; }); }
    }
  }
  Future<void> _newBill() async {
    if (_locked) return;
    // Epoch comes from desktop, never the phone's clock.
    final generation = ++_generation;
    setState(() => _busy = true);
    LanEditorSnapshot? snapshot;
    try { snapshot = await widget.client.editor(widget.connection, widget.commands.token, 'customer', null); }
    catch (error) { _failed(error, generation); }
    finally { if (mounted && generation == _generation) setState(() => _busy = false); }
    if (!mounted || generation != _generation || snapshot == null) return;
    await _submit(LanWriteOperation.sessionCreate, {}, snapshot: snapshot);
  }
  Future<void> _appointmentBill(String id) async {
    await _edit('appointment', id);
    if (!mounted || _editor?.id != id) return;
    await _submit(LanWriteOperation.sessionOpenAppointment, {});
  }
  Future<void> _saveForm() async {
    final editor = _editor;
    if (editor == null || _locked) return;
    if (editor.kind == 'customer') {
      if (_fields['fullName']!.text.trim().isEmpty || _fields['phone']!.text.trim().isEmpty) {
        setState(() => _error = 'Nhập tên và số điện thoại khách hàng.'); return;
      }
      await _submit(editor.id == null ? LanWriteOperation.customerCreate : LanWriteOperation.customerUpdate,
        {for (final entry in _fields.entries) entry.key: entry.value.text.trim()});
    } else if (editor.kind == 'appointment') {
      final duration = int.tryParse(_fields['durationMinutes']!.text);
      if ((_values['customerId'] as String).isEmpty || (_values['employeeId'] as String).isEmpty ||
          (_values['serviceIds'] as List).isEmpty || duration == null) {
        setState(() => _error = 'Chọn khách, dịch vụ, nhân viên và nhập thời lượng hợp lệ.'); return;
      }
      await _submit(editor.id == null ? LanWriteOperation.appointmentCreate : LanWriteOperation.appointmentUpdate, {
        'customerId': _values['customerId'], 'serviceIds': _values['serviceIds'], 'employeeId': _values['employeeId'],
        'status': _values['status'], 'day': _fields['day']!.text.trim(), 'time': _fields['time']!.text.trim(),
        'durationMinutes': duration, 'slotLabel': _fields['slotLabel']!.text.trim(), 'note': _fields['note']!.text.trim()});
    }
  }
  Future<void> _payment() async {
    final allocations = <Map<String, dynamic>>[];
    for (final method in _methods) {
      final amount = int.tryParse(_fields['payment-$method']!.text);
      if (amount == null || amount < 0) { setState(() => _error = 'Nhập số tiền nguyên, không âm.'); return; }
      if (amount > 0) allocations.add({'method': method, 'amount': amount});
    }
    if (allocations.isEmpty && _values['totalAmount'] == 0) allocations.add({'method': 'Tiền mặt', 'amount': 0});
    if (allocations.isEmpty || allocations.fold<int>(0, (sum, a) => sum + (a['amount'] as int)) != _values['totalAmount']) {
      setState(() => _error = 'Tổng các khoản thanh toán phải bằng tổng bill.'); return;
    }
    await _submit(LanWriteOperation.sessionPayment, {'payments': allocations});
  }
  void _numberAction(LanWriteOperation op, String field, {String? lineId}) {
    final number = int.tryParse(_fields[field]!.text);
    if (number == null || number < 0) { setState(() => _error = 'Nhập số tiền nguyên, không âm.'); return; }
    _submit(op, {'amount': number, if (lineId != null) 'lineId': lineId});
  }

  Widget _text(String key, String label, int max, {bool number = false, int lines = 1}) =>
    Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: TextField(
      key: Key('write-$key'), controller: _fields[key], enabled: !_locked,
      maxLength: max, maxLines: lines, keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label)));
  Widget _button(String label, VoidCallback action, {String? key}) => TextButton(
    key: key == null ? null : Key(key), onPressed: _locked ? null : action, child: Text(label));
  Widget _form() {
    if (_editor!.kind == 'customer') {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _text('fullName', 'Tên khách hàng', 120), _text('phone', 'Số điện thoại', 24),
        _text('email', 'Email', 120), _text('tier', 'Hạng khách', 40),
        _text('favoriteService', 'Dịch vụ yêu thích', 200), _text('hairProfile', 'Thông tin tóc', 2000, lines: 3),
        _text('note', 'Ghi chú', 2000, lines: 3),
      ]);
    }
    if (_editor!.kind == 'appointment') {
      final selected = _values['serviceIds'] as List<String>;
      final labels = _values['serviceLabels'] as Map<String, dynamic>;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Khách: ${_values['customerLabel'] ?? ''}'),
        _button('Chọn khách hàng', () => _pick('customers', 'customerId'), key: 'write-pick-customer'),
        Text('Dịch vụ: ${selected.map((id) => labels[id] ?? 'Dịch vụ đã chọn').join(' + ')}'),
        _button('Chọn dịch vụ', () => _pick('services', 'serviceIds'), key: 'write-pick-services'),
        Text('Nhân viên: ${_values['employeeLabel'] ?? ''}'),
        _button('Chọn nhân viên', () => _pick('employees', 'employeeId'), key: 'write-pick-employee'),
        _text('day', 'Ngày hẹn (YYYY-MM-DD)', 10), _text('time', 'Giờ hẹn (HH:mm)', 5),
        _text('durationMinutes', 'Thời lượng (phút)', 4, number: true),
        _text('slotLabel', 'Tên khung giờ', 40), _text('note', 'Ghi chú', 2000, lines: 3),
        const Text('Trạng thái lịch hẹn'),
        Wrap(spacing: 6, children: [for (final status in _statuses)
          ChoiceChip(label: Text(status), selected: _values['status'] == status,
            onSelected: _locked ? null : (_) => setState(() => _values['status'] = status))]),
        if (_editor!.id != null) _button('Lưu riêng trạng thái', () =>
          _submit(LanWriteOperation.appointmentStatus, {'status': _values['status']}), key: 'write-status'),
        if (_editor!.id != null) _button('Lập bill từ lịch hẹn', () =>
          _submit(LanWriteOperation.sessionOpenAppointment, {})),
      ]);
    }
    return _bill();
  }
  Widget _bill() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('Khách: ${_values['customerLabel']}'),
    _button('Chọn khách cho bill', () => _pick('customers', 'billCustomer')),
    Wrap(children: [
      _button('Thêm dịch vụ', () => _pick('services', 'billService'), key: 'bill-add-service'),
      _button('Thêm sản phẩm', () => _pick('products', 'billProduct'), key: 'bill-add-product'),
    ]),
    for (final raw in _values['lines'] as List) _line(Map<String, dynamic>.from(raw as Map)),
    Text('Tạm tính: ${_values['subtotal']} đ · Giảm: ${_values['discountAmount']} đ'),
    Text('Tổng thanh toán: ${_values['totalAmount']} đ', style: Theme.of(context).textTheme.titleLarge),
    if (allows(LanWriteOperation.sessionDiscount)) ...[
      _text('discount', 'Giảm giá bill (đ)', 13, number: true),
      _button('Lưu giảm giá', () => _numberAction(LanWriteOperation.sessionDiscount, 'discount')),
    ],
    if (allows(LanWriteOperation.sessionPayment)) ...[
      const Text('Phân bổ thanh toán (một hoặc nhiều phương thức)'),
      for (final method in _methods) _text('payment-$method', '$method (đ)', 13, number: true),
      _button('Lưu phương thức và số tiền', _payment, key: 'bill-payment'),
      if (!_confirmCheckout) FilledButton(key: const Key('bill-checkout'),
        onPressed: _locked ? null : () => setState(() => _confirmCheckout = true),
        child: const Text('Thanh toán bill')),
      if (_confirmCheckout) ...[
        Text('Chốt bill của ${_values['customerLabel']}: ${_values['totalAmount']} đ? '
          'Kiểm tra dịch vụ, nhân viên, sản phẩm và khoản thanh toán trước khi xác nhận.'),
        FilledButton(key: const Key('bill-confirm-checkout'), onPressed: _locked ? null :
          () => _submit(LanWriteOperation.sessionCheckout, {}), child: const Text('Xác nhận thanh toán')),
        _button('Quay lại kiểm tra', () => setState(() => _confirmCheckout = false)),
      ],
    ] else const Text('Chủ salon cần cấp quyền Thu ngân để thanh toán bill.'),
  ]);
  Widget _line(Map<String, dynamic> line) {
    final id = line['id'] as String;
    final quantity = line['quantity'] as int;
    return Card(child: Padding(padding: const EdgeInsets.all(10), child:
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${line['title']} · $quantity × ${line['unitPrice']} đ = ${line['totalPrice']} đ'),
        Wrap(children: [
          _button('−', () { if (quantity > 1) _submit(LanWriteOperation.sessionQuantity, {'lineId': id, 'quantity': quantity - 1}); }),
          _button('+', () { if (quantity < 1000) _submit(LanWriteOperation.sessionQuantity, {'lineId': id, 'quantity': quantity + 1}); }),
          _button('Xóa dòng', () => _submit(LanWriteOperation.sessionRemoveLine, {'lineId': id})),
          if (line['isService'] == true) ...[
            _button(line['employeeId'] == null ? 'Gán nhân viên' : 'Đổi nhân viên',
              () => _pick('employees', 'billEmployee', lineId: id)),
            if (line['employeeId'] != null) _button('Bỏ gán nhân viên',
              () => _submit(LanWriteOperation.sessionAssignEmployee, {'lineId': id, 'employeeId': null})),
          ],
        ]),
        if (allows(LanWriteOperation.sessionPrice)) ...[
          _text('price-$id', 'Đơn giá (đ)', 13, number: true),
          _button('Lưu đơn giá', () => _numberAction(LanWriteOperation.sessionPrice, 'price-$id', lineId: id)),
        ],
      ])));
  }
  Widget _catalogView() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (!_sessions) _button('Đóng danh sách chọn', () => setState(() { _picker = null; _catalog = null; })),
    if (_picker != 'sessions') TextField(key: const Key('write-catalog-search'), controller: _search,
      maxLength: 80, enabled: !_locked, decoration: InputDecoration(labelText: 'Tìm trong danh sách',
        suffixIcon: IconButton(onPressed: _locked ? null : () { _query = _search.text.trim(); _loadCatalog(); },
          icon: const Icon(Icons.search))), onSubmitted: (v) { _query = v.trim(); _loadCatalog(); }),
    if (_catalog case final page?) ...[
      if (page.items.isEmpty) const Text('Không có mục phù hợp.'),
      for (final item in page.items) ListTile(key: Key('catalog-${item.id}'),
        title: Text(item.title), subtitle: Text(item.subtitle),
        trailing: _pickerField == 'serviceIds' ? Icon((_values['serviceIds'] as List).contains(item.id) ?
          Icons.check_box : Icons.check_box_outline_blank) : const Icon(Icons.chevron_right),
        onTap: _locked ? null : () => _selected(item)),
      Wrap(children: [
        if (_offset > 0) _button('Về đầu', () => _loadCatalog()),
        if (page.nextOffset != null) _button('Trang tiếp', () => _loadCatalog(offset: page.nextOffset!)),
      ]),
    ],
  ]);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Divider(),
    Text('Quyền: ${switch (widget.role) { PhoneWriteRole.none => 'Chỉ xem', PhoneWriteRole.staff => 'Nhân viên',
      PhoneWriteRole.cashier => 'Thu ngân', PhoneWriteRole.owner => 'Chủ salon' }}'),
    if (widget.commands.message != null) Text(widget.commands.message!, key: const Key('write-message')),
    if (widget.commands.pending case final pending?) ...[
      Text('Có thao tác cần kiểm tra: ${pending.operation == LanWriteOperation.sessionCheckout ? 'Thanh toán bill' : 'Lưu dữ liệu'}. '
        'Thao tác mới đang bị khóa để tránh lưu/thanh toán trùng.'),
      TextButton(key: const Key('write-check-result'), onPressed: widget.commands.busy ? null : widget.commands.check,
        child: const Text('Kiểm tra kết quả')),
      if (widget.commands.canRetry) TextButton(key: const Key('write-retry-command'),
        onPressed: widget.commands.busy ? null : widget.commands.retry, child: const Text('Gửi lại đúng thao tác đã lưu')),
      if (widget.commands.oldEpoch) TextButton(onPressed: widget.commands.busy ? null : widget.commands.discardOldEpoch,
        child: const Text('Bỏ thao tác cũ chưa thực hiện')),
    ],
    if (widget.role != PhoneWriteRole.none) Wrap(spacing: 8, children: [
      _button('Thêm khách hàng', () => _edit('customer', null), key: 'write-new-customer'),
      _button('Thêm lịch hẹn', () => _edit('appointment', null), key: 'write-new-appointment'),
      _button('Bill đang làm', _bills, key: 'write-bills'),
      _button('Tạo bill khách vãng lai', _newBill, key: 'write-new-bill'),
    ]),
    if (_busy || widget.commands.busy) const LinearProgressIndicator(),
    if (_error != null) Text(_error!, key: const Key('write-error')),
    if (_editor != null) ...[
      Text(_editor!.kind == 'customer' ? 'Thông tin khách hàng' :
        _editor!.kind == 'appointment' ? 'Thông tin lịch hẹn' : 'Bill đang làm',
        style: Theme.of(context).textTheme.titleLarge),
      const Text('Nếu dữ liệu thay đổi trên desktop, cần tải lại trước khi lưu.'),
      _button('Tải lại và bỏ nội dung chưa lưu', () => _edit(_editor!.kind, _editor!.id), key: 'write-reload'),
      if (_picker == null) _form() else _catalogView(),
      if (_picker == null && _editor!.kind != 'session') FilledButton(key: const Key('write-save'),
        onPressed: _locked ? null : _saveForm, child: const Text('Lưu trên máy salon')),
      _button('Đóng màn hình sửa', () { _clearFields(); setState(() { _editor = null; _picker = null; _readVersion++; }); }),
    ] else if (_sessions) ...[
      _catalogView(), _button('Tải lại bill', () => _loadCatalog()),
      _button('Về dữ liệu salon', () => setState(() { _sessions = false; _picker = null; })),
    ] else CompanionDataPanel(key: ValueKey(_readVersion), connection: widget.connection,
      token: widget.commands.token, client: widget.readClient, onDenied: widget.onDenied,
      onEdit: widget.role == PhoneWriteRole.none || widget.commands.blocked ? null : _edit,
      onOpenAppointment: widget.role == PhoneWriteRole.none || widget.commands.blocked ? null : _appointmentBill),
  ]);

  @override
  void dispose() { _generation++; widget.commands.removeListener(_changed); _clearFields(); _search.dispose(); super.dispose(); }
}
