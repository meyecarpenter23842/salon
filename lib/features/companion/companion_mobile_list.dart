import 'companion_workspace.dart' show CompanionSyncScope;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/lan/lan_contract.dart';
import '../../core/lan/lan_health_client.dart';
import '../../core/lan/lan_pairing.dart';
import '../../core/lan/lan_read_client.dart';
import '../../core/lan/lan_read_models.dart';

class CompanionMobileList extends StatefulWidget {
  const CompanionMobileList({super.key, required this.kind, required this.connection,
    required this.token, required this.client, required this.onDenied, required this.refresh,
    this.today = false, this.onEdit, this.onCreate, this.onBill, this.onBills});
  final SalonReadKind kind;
  final LanConnection connection;
  final String token;
  final SalonReadClient client;
  final VoidCallback onDenied;
  final int refresh;
  final bool today;
  final Future<void> Function(String)? onEdit, onBill;
  final VoidCallback? onCreate, onBills;
  @override
  State<CompanionMobileList> createState() => _CompanionMobileListState();
}
class _CompanionMobileListState extends State<CompanionMobileList> {
  final search = TextEditingController();
  final scroll = ScrollController();
  List<SalonReadRecord> rows = [];
  String query = '';
  String? day, salonDate;
  MobileReadProblem? error;
  int? nextOffset;
  int generation = 0;
  int lastOffset = 0;
  bool busy = false;
  String get title => switch(widget.kind) {
    SalonReadKind.customers => 'khách hàng', SalonReadKind.appointments => 'lịch hẹn', SalonReadKind.invoices => 'hóa đơn',
  };
  @override
  void initState() { super.initState(); _load(); }
  @override
  void didUpdateWidget(CompanionMobileList old) {
    super.didUpdateWidget(old);
    if (old.refresh != widget.refresh) { _load(preserve: true); }
  }
  Future<void> _load({int offset = 0, bool preserve = false}) async {
    final current = ++generation;
    setState(() { busy = true; error = null; });
    try {
      final updated = <SalonReadRecord>[];
      final end = preserve ? lastOffset : offset;
      SalonReadPage? page;
      for (var position = preserve ? 0 : offset; position <= end; position += 25) {
        page = await widget.client.read(widget.connection, widget.token,
          SalonReadQuery(widget.kind, offset: position,
            query: widget.kind == SalonReadKind.customers ? query : '',
            day: widget.kind == SalonReadKind.appointments ? day : null));
        if (!mounted || current != generation) { return; }
        updated.addAll(page.records);
        if (page.nextOffset == null) { break; }
      }
      if (!mounted || current != generation || page == null) { return; }
      final completedPage = page;
      setState(() {
        salonDate = completedPage.salonDate; nextOffset = completedPage.nextOffset;
        rows = offset > 0 && !preserve ? [...rows, ...updated] : updated;
        lastOffset = preserve ? end : offset; busy = false;
      });
    } catch (e) {
      if (!mounted || current != generation) { return; }
      setState(() { busy = false; rows = []; error = MobileReadProblem.from(e, missingMessage: 'Dữ liệu đã thay đổi. Tải lại danh sách.'); });
      if (e is PairingFailure && [LanErrorCode.forbidden, LanErrorCode.unauthenticated].contains(e.code)) { widget.onDenied(); }
    }
  }
  Future<void> _pickDay() async {
    final selected = await showDatePicker(context: context, useRootNavigator: false, initialDate: DateTime.tryParse(day ?? salonDate ?? '') ?? DateTime.now(),
      firstDate: DateTime(2000), lastDate: DateTime(2100), helpText: 'Chọn ngày tại salon');
    if (!mounted || selected == null) { return; }
    day = salonDay(selected); lastOffset = 0;
    if (scroll.hasClients) { scroll.jumpTo(0); }
    await _load();
  }
  Future<void> _detail(SalonReadRecord record) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) =>
      CompanionMobileDetail(kind: widget.kind, id: record.id, connection: widget.connection, token: widget.token,
        client: widget.client, onDenied: widget.onDenied, onEdit: widget.onEdit, onBill: widget.onBill)));
    if (mounted && changed == true) { await _load(preserve: true); }
  }
  void _search(String text) {
    query = text.trim(); lastOffset = 0;
    if (scroll.hasClients) { scroll.jumpTo(0); }
    _load();
  }
  @override
  void dispose() { generation++; search.dispose(); scroll.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (widget.kind == SalonReadKind.customers) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(key: const Key('salon-customer-search'), controller: search, maxLength: 80,
        textInputAction: TextInputAction.search, decoration: InputDecoration(hintText: 'Tên hoặc số điện thoại', counterText: '',
          prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(key: const Key('salon-search'),
            onPressed: () => _search(search.text), icon: const Icon(Icons.arrow_forward))),
        onSubmitted: _search)),
    if (widget.kind == SalonReadKind.appointments) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(key: const Key('salon-pick-day'), onPressed: widget.today ? null : _pickDay,
          icon: const Icon(Icons.calendar_month), label: Text(DateTime.tryParse(day ?? salonDate ?? '') == null ? error != null ? 'Chưa lấy được ngày' : 'Đang tải ngày…' : DateFormat('dd/MM/yyyy').format(DateTime.parse(day ?? salonDate!)))),
        if (!widget.today) TextButton(onPressed: () { day = null; lastOffset = 0; _load(); }, child: const Text('Hôm nay')),
      ])),
    if (widget.onCreate != null || widget.onBills != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(alignment: Alignment.centerLeft, child: FilledButton.icon(
        key: Key(widget.kind == SalonReadKind.customers ? 'write-new-customer' : widget.kind == SalonReadKind.appointments ? 'write-new-appointment' : 'write-bills'),
        onPressed: busy || error != null ? null : widget.onCreate ?? widget.onBills, icon: Icon(widget.onBills != null ? Icons.receipt_long : Icons.add),
        label: Text(widget.onBills != null ? 'Bill đang làm' : widget.kind == SalonReadKind.customers ? 'Thêm khách hàng' : 'Đặt lịch hẹn')))),
    if (busy) const LinearProgressIndicator(),
    Expanded(child: error != null ? MobileStatus(icon: error!.icon, title: error!.title, message: error!.message,
        action: 'Thử lại', onAction: () => _load(preserve: true))
      : !busy && rows.isEmpty ? MobileStatus(icon: widget.kind == SalonReadKind.appointments ? Icons.event_available : Icons.search_off,
          title: widget.today ? 'Hôm nay chưa có lịch hẹn' : 'Chưa có $title phù hợp',
          message: widget.kind == SalonReadKind.customers ? 'Thử tên hoặc số điện thoại khác.' : 'Dữ liệu được cập nhật từ máy salon.',
          action: 'Tải lại', onAction: _load)
      : RefreshIndicator(onRefresh: () => _load(preserve: true), child: ListView.builder(
          controller: scroll, physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: rows.length + 1, itemBuilder: (context, index) {
            if (index == rows.length) {
              return nextOffset == null ? Padding(padding: const EdgeInsets.all(12), child: Text(rows.isEmpty ? '' : 'Đã xem hết $title.', textAlign: TextAlign.center))
                : TextButton(key: const Key('salon-next-page'), onPressed: busy ? null : () => _load(offset: nextOffset!),
                    child: const Text('Xem thêm'));
            }
            final record = rows[index];
            if (widget.kind == SalonReadKind.appointments) {
              final parts = record.title.split(' · ');
              final details = record.subtitle.split(' · ');
              return Card(margin: const EdgeInsets.only(bottom: 12), child: InkWell(key: Key('salon-record-${record.id}'),
                borderRadius: BorderRadius.circular(16), onTap: () => _detail(record),
                child: Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 58, child: Column(children: [
                    const Icon(Icons.schedule, size: 20), const SizedBox(height: 8),
                    FittedBox(fit: BoxFit.scaleDown, child: Text(parts.first, style: const TextStyle(fontWeight: FontWeight.bold))),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(parts.skip(1).join(' · '), style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6), Text(details.length > 1 ? details.take(details.length - 1).join(' · ') : record.subtitle),
                    const SizedBox(height: 8),
                    DecoratedBox(decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Text(details.last, style: Theme.of(context).textTheme.labelLarge))),
                  ])),
                ]))));
            }
            return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(key: Key('salon-record-${record.id}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              leading: CircleAvatar(child: Icon(widget.kind == SalonReadKind.customers ? Icons.person_outline :
                widget.kind == SalonReadKind.appointments ? Icons.schedule : Icons.receipt_long_outlined)),
              title: Text(record.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(record.subtitle)),
              trailing: const Icon(Icons.chevron_right), onTap: () => _detail(record)));
          }))),
  ]);
}

class CompanionMobileDetail extends StatefulWidget {
  const CompanionMobileDetail({super.key, required this.kind, required this.id, required this.connection,
    required this.token, required this.client, required this.onDenied, this.onEdit, this.onBill});
  final SalonReadKind kind;
  final String id, token;
  final LanConnection connection;
  final SalonReadClient client;
  final VoidCallback onDenied;
  final Future<void> Function(String)? onEdit, onBill;
  @override
  State<CompanionMobileDetail> createState() => _CompanionMobileDetailState();
}
class _CompanionMobileDetailState extends State<CompanionMobileDetail> {
  SalonReadRecord? record;
  MobileReadProblem? error;
  int generation = 0;
  int observedGeneration = -1;
  @override void didChangeDependencies() {
    super.didChangeDependencies();
    final commands = CompanionSyncScope.of(context);
    if (commands == null) return;
    final current = commands.dataGeneration;
    if (observedGeneration >= 0 && observedGeneration != current && commands.online && !commands.syncing) { _load(); }
    observedGeneration = current;
  }
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final current = ++generation;
    setState(() { record = null; error = null; });
    try {
      final page = await widget.client.read(widget.connection, widget.token, SalonReadQuery(widget.kind, id: widget.id));
      if (!mounted || current != generation) { return; }
      if (page.records.length != 1) { throw const FormatException('Missing detail'); }
      setState(() => record = page.records.single);
    } catch(e) {
      if (!mounted || current != generation) { return; }
      setState(() => error = MobileReadProblem.from(e, missingMessage: 'Mục này không còn trên máy salon. Quay lại danh sách để tải lại.'));
      if (e is PairingFailure && [LanErrorCode.forbidden, LanErrorCode.unauthenticated].contains(e.code)) { widget.onDenied(); }
    }
  }
  String _sectionFor(String key) => ['Điện thoại', 'Email'].contains(key) ? 'Liên hệ' : ['Ghi chú', 'Hồ sơ tóc'].contains(key) ? 'Ghi chú' : 'Thông tin';
  @override
  void dispose() { generation++; super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.kind == SalonReadKind.customers ? 'Hồ sơ khách hàng' :
      widget.kind == SalonReadKind.appointments ? 'Chi tiết lịch hẹn' : 'Chi tiết hóa đơn')),
    body: SafeArea(child: error != null ? MobileStatus(icon: error!.icon, title: error!.title,
      message: error!.message, action: 'Thử lại', onAction: _load) : record == null ? const Center(child: CircularProgressIndicator())
      : ListView(padding: const EdgeInsets.all(16), children: [
          Text(record!.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8), Text(record!.subtitle), const SizedBox(height: 16),
          if (widget.onEdit != null || widget.onBill != null) Wrap(spacing: 8, runSpacing: 8, children: [
            if (widget.onEdit != null) FilledButton.icon(key: const Key('salon-edit'),
              onPressed: () async { await widget.onEdit!(widget.id); if (mounted) { _load(); } }, icon: const Icon(Icons.edit_outlined), label: const Text('Sửa thông tin')),
            if (widget.onBill != null && record!.fields['Thanh toán'] != 'Đã có hóa đơn thanh toán')
              OutlinedButton.icon(key: const Key('salon-open-bill'), onPressed: () => widget.onBill!(widget.id),
                icon: const Icon(Icons.receipt_long_outlined), label: const Text('Lập bill')),
          ]),
          const SizedBox(height: 16),
          for (final section in ['Liên hệ', 'Thông tin', 'Ghi chú'])
            if (record!.fields.entries.any((e) => _sectionFor(e.key) == section)) Card(child: Padding(padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(section, style: Theme.of(context).textTheme.titleMedium),
              const Divider(),
              for (final e in record!.fields.entries.where((e) => _sectionFor(e.key) == section))
                Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(e.key, style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 3), SelectableText(e.value.isEmpty ? 'Chưa ghi nhận' : e.value)])),
            ]))),
        ])),
  );
}
class MobileStatus extends StatelessWidget {
  const MobileStatus({super.key, required this.icon, required this.title, required this.message,
    required this.action, required this.onAction});
  final IconData icon;
  final String title, message, action;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) => Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 12), Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8), Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 16), FilledButton(onPressed: onAction, child: Text(action)),
    ])));
}

class MobileReadProblem {
  const MobileReadProblem(this.icon, this.title, this.message);
  final IconData icon;
  final String title, message;
  factory MobileReadProblem.from(Object error, {String? missingMessage}) {
    if (error is PairingFailure && error.code == LanErrorCode.unavailable) {
      return const MobileReadProblem(Icons.wifi_off, 'Mất kết nối với máy salon',
        'Kiểm tra Wi-Fi và giữ máy salon mở, rồi thử lại.');
    }
    if (error is PairingFailure && error.code == LanErrorCode.notFound) {
      return MobileReadProblem(Icons.search_off, 'Dữ liệu đã thay đổi',
        missingMessage ?? 'Mục này không còn trên máy salon. Quay lại danh sách để tải lại.');
    }
    return const MobileReadProblem(Icons.error_outline, 'Chưa tải được dữ liệu',
      'Thử tải lại. Nếu lỗi còn xuất hiện, kiểm tra dữ liệu trên máy salon.');
  }
}

