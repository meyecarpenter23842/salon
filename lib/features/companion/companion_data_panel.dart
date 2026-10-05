import 'package:flutter/material.dart';

import '../../core/lan/lan_contract.dart';
import '../../core/lan/lan_health_client.dart';
import '../../core/lan/lan_pairing.dart';
import '../../core/lan/lan_read_client.dart';
import '../../core/lan/lan_read_models.dart';

/// Memory-only data. The access panel unmounts this on loss of connection,
/// permission, app foreground or pairing. No local business database is opened.
class CompanionDataPanel extends StatefulWidget {
  const CompanionDataPanel({super.key, required this.connection,
    required this.token, required this.client, required this.onDenied,
    this.onEdit, this.onOpenAppointment});
  final LanConnection connection;
  final String token;
  final SalonReadClient client;
  final VoidCallback onDenied;
  final void Function(String kind, String id)? onEdit;
  final ValueChanged<String>? onOpenAppointment;
  @override
  State<CompanionDataPanel> createState() => _CompanionDataPanelState();
}

class _CompanionDataPanelState extends State<CompanionDataPanel> {
  SalonReadKind _kind = SalonReadKind.customers;
  final _search = TextEditingController();
  String _query = '';
  String? _day;
  String? _salonDate;
  SalonReadPage? _page;
  SalonReadRecord? _detail;
  bool _busy = false;
  String? _error;
  int _generation = 0;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int offset = 0, String? id}) async {
    final generation = ++_generation;
    setState(() { _busy = true; _error = null; _page = null; _detail = null; });
    try {
      final page = await widget.client.read(widget.connection, widget.token,
        SalonReadQuery(_kind, offset: offset, id: id,
          query: id == null && _kind == SalonReadKind.customers ? _query : '',
          day: id == null && _kind == SalonReadKind.appointments ? _day : null));
      if (!mounted || generation != _generation) return;
      setState(() {
        _salonDate = page.salonDate;
        _offset = offset;
        if (id != null) {
          if (page.records.length != 1) throw const FormatException('Missing detail');
          _detail = page.records.single;
        } else { _page = page; }
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error is PairingFailure && error.code == LanErrorCode.notFound
        ? 'Mục này không còn trên máy salon. Hãy tải lại danh sách.'
        : 'Chưa tải được dữ liệu. Kiểm tra kết nối và thử lại.');
      if (error is PairingFailure &&
          (error.code == LanErrorCode.forbidden || error.code == LanErrorCode.unauthenticated)) {
        widget.onDenied();
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _choose(SalonReadKind kind) {
    if (_kind == kind && _detail == null) return;
    setState(() { _kind = kind; _query = ''; _search.clear(); _day = null; });
    _load();
  }

  Future<void> _pickDay() async {
    final initial = DateTime.tryParse(_day ?? _salonDate ?? '') ?? DateTime.now();
    final selected = await showDatePicker(context: context, initialDate: initial,
      firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (!mounted || selected == null) return;
    setState(() => _day = salonDay(selected));
    _load();
  }

  @override
  void dispose() { _generation++; _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(),
      Text(widget.onEdit == null ? 'Dữ liệu từ máy salon · Chỉ xem' : 'Dữ liệu từ máy salon'),
      Wrap(spacing: 8, children: [
        for (final kind in SalonReadKind.values)
          ChoiceChip(key: Key('salon-tab-${kind.name}'),
            label: Text(switch (kind) {
              SalonReadKind.customers => 'Khách hàng',
              SalonReadKind.invoices => 'Hóa đơn',
              SalonReadKind.appointments => 'Lịch hẹn',
            }), selected: _kind == kind, onSelected: (_) => _choose(kind)),
      ]),
      if (_detail == null && _kind == SalonReadKind.customers)
        TextField(key: const Key('salon-customer-search'), controller: _search,
          maxLength: 80, textInputAction: TextInputAction.search,
          decoration: InputDecoration(labelText: 'Tìm tên hoặc số điện thoại',
            suffixIcon: IconButton(key: const Key('salon-search'), icon: const Icon(Icons.search),
              onPressed: () { _query = _search.text.trim(); _load(); })),
          onSubmitted: (value) { _query = value.trim(); _load(); }),
      if (_detail == null && _kind == SalonReadKind.invoices)
        const Text('Hóa đơn đã thanh toán, mới nhất trước.'),
      if (_detail == null && _kind == SalonReadKind.appointments) ...[
        Text('Ngày trên máy salon: ${_day ?? _salonDate ?? 'Đang tải…'}'),
        Wrap(spacing: 8, children: [
          TextButton.icon(key: const Key('salon-pick-day'),
            onPressed: _pickDay, icon: const Icon(Icons.calendar_month),
            label: const Text('Chọn ngày')),
          TextButton(onPressed: () { _day = null; _load(); },
            child: const Text('Hôm nay tại salon')),
        ]),
      ],
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!, key: const Key('salon-read-error')),
      if (_detail case final detail?) ...[
        TextButton.icon(key: const Key('salon-detail-back'),
          onPressed: () => _load(), icon: const Icon(Icons.arrow_back),
          label: const Text('Về danh sách')),
        Text(detail.title, style: Theme.of(context).textTheme.titleLarge),
        Text(detail.subtitle),
        if (widget.onEdit != null && _kind != SalonReadKind.invoices)
          FilledButton.tonal(key: const Key('salon-edit'), onPressed: () => widget.onEdit!(
            _kind == SalonReadKind.customers ? 'customer' : 'appointment', detail.id),
            child: const Text('Sửa thông tin')),
        if (widget.onOpenAppointment != null && _kind == SalonReadKind.appointments)
          FilledButton.tonal(key: const Key('salon-open-bill'),
            onPressed: () => widget.onOpenAppointment!(detail.id), child: const Text('Lập bill từ lịch hẹn')),
        for (final field in detail.fields.entries)
          Padding(padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('${field.key}: ${field.value.isEmpty ? '—' : field.value}')),
      ],
      if (_page case final page?) ...[
        if (page.records.isEmpty)
          const Text('Không có dữ liệu phù hợp.', key: Key('salon-empty')),
        for (final record in page.records)
          ListTile(key: Key('salon-record-${record.id}'), contentPadding: EdgeInsets.zero,
            title: Text(record.title), subtitle: Text(record.subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _load(id: record.id)),
        Wrap(spacing: 8, children: [
          if (_offset > 0) TextButton(key: const Key('salon-first-page'),
            onPressed: () => _load(), child: const Text('Về đầu danh sách')),
          if (page.nextOffset != null) TextButton(key: const Key('salon-next-page'),
            onPressed: () => _load(offset: page.nextOffset!), child: const Text('Trang tiếp')),
        ]),
      ],
      TextButton.icon(key: const Key('salon-data-refresh'),
        onPressed: _busy ? null : () => _load(id: _detail?.id),
        icon: const Icon(Icons.refresh), label: const Text('Tải lại dữ liệu')),
    ],
  );
}
