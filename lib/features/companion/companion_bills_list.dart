import 'companion_workspace.dart' show CompanionSyncScope;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/lan/lan_contract.dart';
import '../../core/lan/lan_health_client.dart';
import '../../core/lan/lan_pairing.dart';
import '../../core/lan/lan_read_client.dart';
import '../../core/lan/lan_read_models.dart';
import '../../core/lan/lan_workflow_client.dart';
import '../../core/lan/lan_workflow_models.dart';
import 'companion_bill_ui.dart';
import 'companion_mobile_list.dart';

class CompanionBillsList extends StatefulWidget {
  const CompanionBillsList({super.key, required this.connection, required this.token,
    required this.readClient, required this.client, required this.onDenied, required this.refresh,
    required this.onOpen, this.onCreate});
  final LanConnection connection;
  final String token;
  final SalonReadClient readClient;
  final LanWorkflowClient client;
  final VoidCallback onDenied;
  final int refresh;
  final Future<void> Function(String) onOpen;
  final Future<void> Function()? onCreate;
  @override State<CompanionBillsList> createState() => _CompanionBillsListState();
}
class _CompanionBillsListState extends State<CompanionBillsList> {
  final search = [TextEditingController(), TextEditingController()];
  final scroll = [ScrollController(), ScrollController()];
  final queries = ['', ''];
  final active = <LanCatalogItem>[];
  final paid = <SalonReadRecord>[];
  final lastOffsets = [0, 0];
  final nextOffsets = <int?>[null, null];
  int section = 0, generation = 0;
  String? day, salonDate;
  bool busy = false;
  MobileReadProblem? error;
  @override void initState() { super.initState(); _load(); }
  @override void didUpdateWidget(CompanionBillsList old) {
    super.didUpdateWidget(old); if (old.refresh != widget.refresh) { _load(preserve: true); }
  }
  Future<void> _load({int offset = 0, bool preserve = false}) async {
    final current = ++generation, target = section;
    setState(() { busy = true; error = null; });
    try {
      final sessions = <LanCatalogItem>[], invoices = <SalonReadRecord>[];
      int? next;
      final end = preserve ? lastOffsets[target] : offset;
      for (var position = preserve ? 0 : offset; position <= end; position += 25) {
        if (target == 0) {
          final page = await widget.client.catalog(widget.connection, widget.token, 'sessions', queries[0], position);
          sessions.addAll(page.items); next = page.nextOffset;
        } else {
          final page = await widget.readClient.read(widget.connection, widget.token,
            SalonReadQuery(SalonReadKind.invoices, query: queries[1], day: day, offset: position));
          invoices.addAll(page.records); next = page.nextOffset; salonDate = page.salonDate;
        }
        if (!mounted || current != generation) { return; }
        if (next == null) { break; }
      }
      if (!mounted || current != generation) { return; }
      setState(() {
        if (offset == 0 || preserve) { (target == 0 ? active : paid).clear(); }
        if (target == 0) { active.addAll(sessions); } else { paid.addAll(invoices); }
        nextOffsets[target] = next; lastOffsets[target] = end; busy = false;
      });
    } catch(e) {
      if (!mounted || current != generation) { return; }
      setState(() { busy = false; error = MobileReadProblem.from(e); });
      if (e is PairingFailure && [LanErrorCode.forbidden, LanErrorCode.unauthenticated].contains(e.code)) { widget.onDenied(); }
    }
  }
  Future<void> _pickDay() async {
    final selected = await showDatePicker(context: context, useRootNavigator: false,
      initialDate: DateTime.tryParse(day ?? salonDate ?? '') ?? DateTime.now(),
      firstDate: DateTime(2000), lastDate: DateTime(2100), helpText: 'Ngày thanh toán tại salon');
    if (!mounted || selected == null) { return; }
    day = salonDay(selected); lastOffsets[1] = 0; await _load();
  }
  Future<void> _open(int index) async {
    if (section == 0) { await widget.onOpen(active[index].id); }
    else {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
        CompanionReceipt(connection: widget.connection, token: widget.token, client: widget.readClient,
          id: paid[index].id, onDenied: widget.onDenied)));
    }
    if (mounted) { await _load(preserve: true); }
  }
  @override void dispose() {
    generation++; for (final c in search) { c.dispose(); } for (final c in scroll) { c.dispose(); } super.dispose();
  }
  @override Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Row(children: [
      Expanded(child: ChoiceChip(key: const Key('bill-list-active'), label: const Text('Đang làm'),
        selected: section == 0, onSelected: (_) { FocusManager.instance.primaryFocus?.unfocus(); section = 0; _load(preserve: true); })),
      const SizedBox(width: 8),
      Expanded(child: ChoiceChip(key: const Key('bill-list-paid'), label: const Text('Đã thanh toán'),
        selected: section == 1, onSelected: (_) { FocusManager.instance.primaryFocus?.unfocus(); section = 1; _load(preserve: true); })),
    ])),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: TextField(
      key: ValueKey('bill-list-search-$section'), controller: search[section], maxLength: 80,
      textInputAction: TextInputAction.search, decoration: InputDecoration(hintText: 'Tên, số điện thoại hoặc mã bill',
        counterText: '', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(key: const Key('bill-list-find'),
          onPressed: () { queries[section] = search[section].text.trim(); lastOffsets[section] = 0;
            FocusManager.instance.primaryFocus?.unfocus(); _load(); }, icon: const Icon(Icons.arrow_forward))),
      onSubmitted: (value) { queries[section] = value.trim(); lastOffsets[section] = 0; _load(); })),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Align(alignment: Alignment.centerLeft,
      child: Wrap(spacing: 8, runSpacing: 4, children: [
        if (section == 0 && widget.onCreate != null) FilledButton.icon(key: const Key('write-new-bill'),
          onPressed: busy || error != null ? null : () async { await widget.onCreate!(); if (mounted) { _load(preserve: true); } },
          icon: const Icon(Icons.add), label: const Text('Bill mới')),
        if (section == 1) OutlinedButton.icon(key: const Key('bill-list-day'), onPressed: _pickDay,
          icon: const Icon(Icons.calendar_month), label: Text(day == null ? 'Tất cả ngày' : DateFormat('dd/MM/yyyy').format(DateTime.parse(day!)))),
        if (section == 1 && day != null) TextButton(onPressed: () { day = null; lastOffsets[1] = 0; _load(); }, child: const Text('Bỏ lọc ngày')),
      ]))),
    if (busy) const LinearProgressIndicator(),
    Expanded(child: error != null ? MobileStatus(icon: error!.icon, title: error!.title, message: error!.message,
      action: 'Thử lại', onAction: () => _load(preserve: true))
      : !busy && (section == 0 ? active.isEmpty : paid.isEmpty)
        ? MobileStatus(icon: Icons.receipt_long_outlined, title: section == 0 ? 'Chưa có bill đang làm' : 'Chưa có hóa đơn phù hợp',
          message: 'Thử tìm kiếm khác hoặc tải lại dữ liệu từ máy salon.', action: 'Tải lại', onAction: _load)
        : RefreshIndicator(onRefresh: () => _load(preserve: true), child: ListView.builder(
          key: PageStorageKey('bill-list-$section'), controller: scroll[section],
          physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: (section == 0 ? active.length : paid.length) + 1, itemBuilder: (context, index) {
            final length = section == 0 ? active.length : paid.length;
            if (index == length) { return nextOffsets[section] == null ? const SizedBox(height: 16)
              : TextButton(key: const Key('bill-list-next'), onPressed: busy ? null : () => _load(offset: nextOffsets[section]!),
                child: const Text('Xem thêm')); }
            final id = section == 0 ? active[index].id : paid[index].id;
            return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(key: ValueKey('bill-list-$id'),
              leading: Icon(section == 0 ? Icons.receipt_long_outlined : Icons.check_circle_outline),
              title: Text(section == 0 ? active[index].title : paid[index].title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(section == 0
                ? '${active[index].totalAmount == null ? active[index].subtitle : billMoney(active[index].totalAmount!)} · ${active[index].lineCount ?? '—'} dòng\n${billDate(active[index].updatedAt)}'
                : paid[index].subtitle), isThreeLine: section == 0, trailing: const Icon(Icons.chevron_right),
              onTap: busy ? null : () => _open(index)));
          }))),
  ]);
}

class CompanionReceipt extends StatefulWidget {
  const CompanionReceipt({super.key, required this.connection, required this.token, required this.client,
    required this.id, required this.onDenied, this.success = false});
  final LanConnection connection;
  final String token, id;
  final SalonReadClient client;
  final VoidCallback onDenied;
  final bool success;
  @override State<CompanionReceipt> createState() => _CompanionReceiptState();
}
class _CompanionReceiptState extends State<CompanionReceipt> {
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
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final current = ++generation;
    setState(() { error = null; });
    try {
      final page = await widget.client.read(widget.connection, widget.token, SalonReadQuery(SalonReadKind.invoices, id: widget.id));
      if (!mounted || current != generation) { return; }
      if (page.records.length != 1) { throw const PairingFailure(LanErrorCode.notFound); }
      setState(() => record = page.records.single);
    } catch(e) {
      if (!mounted || current != generation) { return; }
      setState(() => error = MobileReadProblem.from(e));
      if (e is PairingFailure && [LanErrorCode.forbidden, LanErrorCode.unauthenticated].contains(e.code)) { widget.onDenied(); }
    }
  }
  @override void dispose() { generation++; super.dispose(); }
  @override Widget build(BuildContext context) {
    final fields = record?.fields ?? <String, String>{};
    final lines = fields.entries.where((e) => RegExp(r'^\d+\. ').hasMatch(e.key)).toList();
    final payments = fields.entries.where((e) => e.key.startsWith('Thanh toán ') && e.key != 'Thanh toán lúc').toList();
    return Scaffold(appBar: AppBar(title: Text(widget.success ? 'Đã thanh toán' : 'Chi tiết hóa đơn')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.success) billGroup(context, 'Thanh toán thành công', [
          const Icon(Icons.check_circle, color: Colors.green, size: 48),
          const SizedBox(height: 8), const Text('Máy salon đã ghi nhận hóa đơn.'),
          SelectableText('Mã hóa đơn: ${widget.id}'),
        ]),
        if (error != null) MobileStatus(icon: error!.icon, title: error!.title,
          message: widget.success ? 'Thanh toán đã được ghi nhận. Chưa tải được chi tiết biên nhận; thử tải lại, không thanh toán lại.' : error!.message,
          action: 'Tải biên nhận', onAction: _load)
        else if (record == null) const Center(child: CircularProgressIndicator())
        else ...[
          billGroup(context, 'Thông tin hóa đơn', [
            Text(record!.title, style: Theme.of(context).textTheme.titleLarge),
            for (final key in ['Mã hóa đơn', 'Thanh toán lúc', 'Trạng thái'])
              if (fields[key] != null && !(widget.success && key == 'Mã hóa đơn')) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText('$key: ${fields[key]}')),
          ]),
          billGroup(context, 'Dịch vụ và sản phẩm', [
            for (final line in lines) Padding(padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(line.key, style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(line.value),
              ])),
            if (lines.isEmpty) const Text('Không có chi tiết dòng trong biên nhận.'),
          ]),
          billGroup(context, 'Tổng tiền', [
            for (final key in ['Tạm tính', 'Giảm giá hóa đơn', 'Tổng hóa đơn', 'Số tiền điều chỉnh'])
              if (fields[key] != null) billAmountRow(key, fields[key]!, strong: key == 'Tổng hóa đơn'),
          ]),
          billGroup(context, 'Thanh toán', [
            if (payments.isEmpty) Text(fields['Phương thức'] ?? 'Chưa có thông tin phương thức'),
            for (final p in payments) billAmountRow(p.key.replaceFirst('Thanh toán ', ''), p.value),
          ]),
        ],
      ])),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: FilledButton(
        key: const Key('bill-receipt-done'), onPressed: () => Navigator.of(context).pop(true), child: const Text('Quay lại công việc')))));
  }
}

