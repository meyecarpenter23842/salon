import '../../../../core/providers/repository_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../../../core/models/audit_event.dart';
import '../../../../core/models/entity_id.dart';
import '../../../../core/models/inventory_item.dart';
import '../../../../core/models/stock_document.dart';
import '../../../../core/providers/data_backend_provider.dart';
import '../../../../core/providers/inventory_providers.dart';
import '../../../../core/providers/stock_document_providers.dart';
import '../../../../shared/widgets/sensitive_action_authorization.dart';
import 'stock_document_pdf.dart';

String stockMoney(int value) => '${NumberFormat.decimalPattern('vi_VN').format(value)} đ';
void refreshStockDocuments(WidgetRef ref) {
  ref.invalidate(securityAuditEventsProvider);
  ref.read(stockDocumentsNonceProvider.notifier).state++;
  ref.read(inventoryRefreshNonceProvider.notifier).state++;
}
Future<StockDocument?> openStockDocumentEditor(BuildContext context, WidgetRef ref, {
    required StockDocumentKind kind, StockDocument? existing, List<InventoryProductItem> seeds = const []}) async {
  if (!await ensureSensitiveActionAuthorized(context, ref, SensitiveAction.stockDocument) || !context.mounted) { return null; }
  try {
    final products = await ref.read(inventoryRepositoryProvider).fetchInventoryProducts();
    if (seeds.any((seed) => !products.any((p) => p.id == seed.id && p.isActive))) {
      throw StateError('Sản phẩm đã ngừng kinh doanh. Bật lại sản phẩm trước khi lập phiếu.');
    }
    final suppliers = await ref.read(stockDocumentRepositoryProvider).suppliers(includeInactive: false);
    if (!context.mounted) { return null; }
    final doc = await showDialog<StockDocument>(context: context, barrierDismissible: false,
      builder: (_) => StockDocumentEditor(kind: kind, existing: existing,
        products: products.where((p) => p.isActive).toList(), suppliers: suppliers, seeds: seeds));
    if (doc != null && context.mounted) { refreshStockDocuments(ref); }
    return doc;
  } catch (e) {
    if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không mở được phiếu: $e'))); }
    return null;
  }
}

class StockDocumentsPage extends ConsumerStatefulWidget {
  const StockDocumentsPage({super.key, this.receipts = true});
  final bool receipts;
  @override
  ConsumerState<StockDocumentsPage> createState() => _StockDocumentsPageState();
}
class _StockDocumentsPageState extends ConsumerState<StockDocumentsPage> {
  String query = '';
  String status = 'all';
  int offset = 0;
  @override
  Widget build(BuildContext context) {
    if (ref.watch(appDataBackendProvider) == AppDataBackend.fake) {
      return const Center(child: Text('Chứng từ kho cần chuyển sang dữ liệu salon.'));
    }
    final state = ref.watch(stockDocumentPageProvider((query: query, status: status, receipts: widget.receipts, offset: offset)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.spaceBetween, children: [
        Text(widget.receipts ? 'Phiếu nhập kho' : 'Phiếu xuất và kiểm kê', style: Theme.of(context).textTheme.titleLarge),
        if (widget.receipts) FilledButton.icon(key: const Key('stock-new-receipt'),
          onPressed: () => _create(StockDocumentKind.receipt), icon: const Icon(Icons.add), label: const Text('Lập phiếu nhập')),
        if (!widget.receipts) ...[
          FilledButton(onPressed: () => _create(StockDocumentKind.issue), child: const Text('Lập phiếu xuất')),
          OutlinedButton(onPressed: () => _create(StockDocumentKind.adjustment), child: const Text('Lập phiếu kiểm kê')),
        ],
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(decoration: const InputDecoration(isDense: true, labelText: 'Tìm mã phiếu, NCC, người lập, chứng từ ngoài'),
          onChanged: (v) => setState(() { query = v; offset = 0; }))),
        const SizedBox(width: 8),
        SizedBox(width: 150, child: DropdownButtonFormField<String>(initialValue: status,
          decoration: const InputDecoration(isDense: true, labelText: 'Trạng thái'),
          items: const [DropdownMenuItem(value: 'all', child: Text('Tất cả')), DropdownMenuItem(value: 'draft', child: Text('Nháp')),
            DropdownMenuItem(value: 'posted', child: Text('Đã ghi kho')), DropdownMenuItem(value: 'cancelled', child: Text('Đã hủy'))],
          onChanged: (v) => setState(() { status = v ?? 'all'; offset = 0; }))),
      ]),
      const SizedBox(height: 10),
      Expanded(child: state.when(loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: TextButton(onPressed: () => ref.read(stockDocumentsNonceProvider.notifier).state++, child: Text('Không tải được phiếu. Tải lại: $e'))),
        data: (docs) {
          final q = query.trim().toLowerCase();
          final filtered = docs.where((d) => (widget.receipts == (d.kind == StockDocumentKind.receipt)) &&
            (status == 'all' || d.status == status) && [d.number, d.supplierName, d.preparedBy, d.externalReference]
              .any((v) => v.toLowerCase().contains(q))).toList();
          if (filtered.isEmpty) { return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Chưa có phiếu phù hợp. Lập phiếu rồi lưu nháp trước khi xác nhận.'),
            if (offset > 0) TextButton(onPressed: () => setState(() => offset = 0), child: const Text('Về trang đầu')),
          ])); }
          return Column(children: [Expanded(child: ListView.separated(itemCount: filtered.length, separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = filtered[i];
              return ListTile(key: Key('stock-document-${d.id}'), leading: Icon(d.isDraft ? Icons.edit_note : d.isPosted ? Icons.inventory_2_outlined : Icons.undo),
                title: Text('${d.number} • ${d.kind.label} • ${d.statusLabel}'),
                subtitle: Text('${DateFormat('dd/MM/yyyy').format(d.date)} • ${d.supplierName.isEmpty ? 'Không ghi nhận NCC' : d.supplierName} • ${d.preparedBy}'),
                trailing: Text(stockMoney(d.total)), onTap: () => showStockDocument(context, ref, d));
            })), Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton(onPressed: offset == 0 ? null : () => setState(() => offset = (offset - 50).clamp(0, 1000000)), child: const Text('Trang trước')),
              Text('Trang ${offset ~/ 50 + 1}'),
              TextButton(onPressed: docs.length < 50 ? null : () => setState(() => offset += 50), child: const Text('Trang sau')),
            ])]);
        })),
    ]);
  }
  Future<void> _create(StockDocumentKind kind) async {
    final doc = await openStockDocumentEditor(context, ref, kind: kind);
    if (doc != null && mounted) { await showStockDocument(context, ref, doc); }
  }
}

Future<void> showStockDocument(BuildContext context, WidgetRef ref, StockDocument doc) =>
  showDialog<void>(context: context, builder: (_) => StockDocumentDetail(initial: doc));

class StockDocumentDetail extends ConsumerStatefulWidget {
  const StockDocumentDetail({super.key, required this.initial});
  final StockDocument initial;
  @override
  ConsumerState<StockDocumentDetail> createState() => _StockDocumentDetailState();
}
class _StockDocumentDetailState extends ConsumerState<StockDocumentDetail> {
  late StockDocument doc;
  bool busy = false;
  bool confirming = false;
  String? error;
  @override
  void initState() { super.initState(); doc = widget.initial; }
  Future<void> _action(bool cancel) async {
    if (busy || confirming) { return; }
    confirming = true;
    if (!await ensureSensitiveActionAuthorized(context, ref, SensitiveAction.stockDocument) || !mounted) { confirming = false; return; }
    final reason = TextEditingController();
    final approved = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(cancel ? 'Hủy phiếu ${doc.number}?' : 'Xác nhận ghi kho ${doc.number}?'),
      content: cancel ? TextField(controller: reason, maxLength: 2000, decoration: const InputDecoration(labelText: 'Lý do hủy bắt buộc'))
        : Text('Toàn bộ ${doc.lines.length} dòng sẽ được ghi vào kho. Giá trị: ${stockMoney(doc.total)}. Không ghi chi tiền/công nợ.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Quay lại')),
        FilledButton(onPressed: () { if (!cancel || reason.text.trim().isNotEmpty) { Navigator.pop(dialogContext, true); } },
          child: Text(cancel ? 'Hủy phiếu' : 'Ghi kho'))]));
    final text = reason.text;
    await Future<void>.delayed(const Duration(milliseconds: 300)); reason.dispose();
    confirming = false;
    if (approved != true || !mounted) { return; }
    setState(() { busy = true; error = null; });
    try {
      final repo = ref.read(stockDocumentRepositoryProvider);
      final result = cancel ? await repo.cancel(doc.id, expectedRevision: doc.revision, reason: text)
        : await repo.post(doc.id, expectedRevision: doc.revision);
      if (mounted) { refreshStockDocuments(ref); setState(() => doc = result); }
    } catch (e) { if (mounted) { setState(() => error = '$e'); } }
    finally { if (mounted) { setState(() => busy = false); } }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: AlertDialog(
    title: Text('${doc.number} • ${doc.statusLabel}'),
    content: SizedBox(width: 780, height: MediaQuery.sizeOf(context).height * .65,
      child: ListView(children: [
        Text('${doc.kind.label} • Ngày ${DateFormat('dd/MM/yyyy').format(doc.date)}'),
        Text('NCC: ${doc.supplierName.isEmpty ? 'Không ghi nhận' : doc.supplierName}'),
        Text('Người lập: ${doc.preparedBy} • Ghi kho: ${doc.postedBy}'),
        Text('Chứng từ ngoài: ${doc.externalReference}'), Text('Ghi chú: ${doc.note}'),
        if (doc.cancellationReason.isNotEmpty) Text('Lý do hủy: ${doc.cancellationReason}'),
        const Divider(),
        for (final line in doc.lines) ListTile(dense: true, title: Text(line.productName),
          subtitle: Text('${line.quantity} ${line.unitName.isEmpty ? '(chưa thiết lập đơn vị)' : line.unitName} × ${stockMoney(line.unitCost)}'),
          trailing: Text(stockMoney(line.amount))),
        Text('Tổng giá trị: ${stockMoney(doc.total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const Text('Giá nhập không thay giá bán. Phiếu này không ghi chi tiền hoặc công nợ.'),
        if (doc.isDraft) const Text('Nháp — chưa thay đổi tồn kho.'),
        if (!doc.isDraft) _DocumentMovementList(documentId: doc.id),
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ])),
    actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Đóng')),
      if (doc.isDraft) TextButton(onPressed: busy ? null : () async {
        final updated = await openStockDocumentEditor(context, ref, kind: doc.kind, existing: doc);
        if (updated != null && mounted) { setState(() => doc = updated); }
      }, child: const Text('Sửa nháp')),
      TextButton(onPressed: busy ? null : () => showDialog<void>(context: context, builder: (_) => Dialog(
        child: SizedBox(width: 850, height: MediaQuery.sizeOf(context).height * .8,
          child: PdfPreview(pdfFileName: '${doc.number}.pdf', canChangeOrientation: false, canChangePageFormat: false,
            build: (_) => buildStockDocumentPdf(doc))))), child: const Text('Xem / in PDF')),
      if (doc.status != 'cancelled') OutlinedButton(key: const Key('stock-cancel'), onPressed: busy ? null : () => _action(true), child: const Text('Hủy phiếu')),
      if (doc.isDraft) FilledButton(key: const Key('stock-post'), onPressed: busy ? null : () => _action(false), child: Text(busy ? 'Đang ghi…' : 'Xác nhận ghi kho')),
    ]));
}
final stockDocumentMovementsProvider = FutureProvider.family<List<InventoryMovementItem>, String>((ref, id) {
  ref.watch(stockDocumentsNonceProvider);
  return ref.watch(stockDocumentRepositoryProvider).movementHistory(documentId: id, limit: 500);
});
class _DocumentMovementList extends ConsumerWidget {
  const _DocumentMovementList({required this.documentId});
  final String documentId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(stockDocumentMovementsProvider(documentId)).when(
    loading: () => const CircularProgressIndicator(), error: (e, _) => Text('Không tải được bút toán: $e'),
    data: (items) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Divider(), const Text('Bút toán đối chiếu chứng từ', style: TextStyle(fontWeight: FontWeight.bold)),
      for (final m in items) Text('${m.movementLabel} • ${m.productName} • ${m.stockBefore} → ${m.stockAfter} (${m.quantityDeltaLabel})'),
    ]));
}

class _StockLineEditor {
  _StockLineEditor(this.productId, int quantity, int cost) : quantity = TextEditingController(text: '$quantity'), cost = TextEditingController(text: '$cost');
  String? productId;
  final TextEditingController quantity, cost;
  void dispose() { quantity.dispose(); cost.dispose(); }
}
class StockDocumentEditor extends ConsumerStatefulWidget {
  const StockDocumentEditor({super.key, required this.kind, required this.products, required this.suppliers, this.existing, this.seeds = const []});
  final StockDocumentKind kind;
  final List<InventoryProductItem> products, seeds;
  final List<StockSupplier> suppliers;
  final StockDocument? existing;
  @override
  ConsumerState<StockDocumentEditor> createState() => _StockDocumentEditorState();
}
class _StockDocumentEditorState extends ConsumerState<StockDocumentEditor> {
  final form = GlobalKey<FormState>();
  final lines = <_StockLineEditor>[];
  late final TextEditingController prepared, external, note;
  late final String id;
  late DateTime date;
  String? supplier;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    id = d?.id ?? EntityId.create('stock_document');
    date = d?.date ?? DateTime.now();
    supplier = widget.suppliers.any((s) => s.id == d?.supplierId) ? d?.supplierId : null;
    prepared = TextEditingController(text: d?.preparedBy ?? 'Chủ salon');
    external = TextEditingController(text: d?.externalReference ?? '');
    note = TextEditingController(text: d?.note ?? '');
    if (d != null) {
      lines.addAll(d.lines.map((l) => _StockLineEditor(widget.products.any((p) => p.id == l.productId) ? l.productId : null, l.quantity, l.unitCost)));
    } else if (widget.seeds.isNotEmpty) {
      lines.addAll(widget.seeds.map((p) => _StockLineEditor(p.id,
        widget.kind == StockDocumentKind.adjustment ? (p.stockOnHand < 0 ? 0 : p.stockOnHand) : 1, 0)));
    } else { lines.add(_StockLineEditor(null, 1, 0)); }
  }
  @override
  void dispose() { prepared.dispose(); external.dispose(); note.dispose(); for (final l in lines) { l.dispose(); } super.dispose(); }
  int get total => lines.fold(0, (sum, l) => sum + (int.tryParse(l.quantity.text) ?? 0) * (int.tryParse(l.cost.text) ?? 0));
  Future<void> save() async {
    if (busy || !form.currentState!.validate()) { return; }
    setState(() { busy = true; error = null; });
    try {
      final result = await ref.read(stockDocumentRepositoryProvider).saveDraft(StockDocumentInput(
        id: id, kind: widget.kind, date: DateTime(date.year, date.month, date.day), preparedBy: prepared.text,
        supplierId: supplier, externalReference: external.text, note: note.text, expectedRevision: widget.existing?.revision,
        lines: lines.map((l) => StockDocumentLineInput(productId: l.productId!, quantity: int.parse(l.quantity.text),
          unitCost: widget.kind == StockDocumentKind.receipt ? int.parse(l.cost.text) : 0)).toList()));
      if (mounted) { Navigator.pop(context, result); }
    } catch (e) { if (mounted) { setState(() { busy = false; error = '$e'; }); } }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !busy, child: AlertDialog(
    title: Text('${widget.kind.label} • ${widget.existing?.number ?? 'Lập nháp'}'),
    content: SizedBox(width: 760, height: MediaQuery.sizeOf(context).height * .65, child: Form(key: form,
      child: ListView(children: [
        OutlinedButton.icon(onPressed: busy ? null : () async {
          final value = await showDatePicker(context: context, initialDate: date,
            firstDate: DateTime(2000), lastDate: DateTime(2100));
          if (value != null && mounted) { setState(() => date = value); }
        }, icon: const Icon(Icons.calendar_month), label: Text('Ngày: ${DateFormat('dd/MM/yyyy').format(date)}')),
        TextFormField(controller: prepared, enabled: !busy, maxLength: 200, decoration: const InputDecoration(labelText: 'Người lập'),
          validator: (v) => v == null || v.trim().isEmpty ? 'Nhập người lập' : null),
        if (widget.kind == StockDocumentKind.receipt) DropdownButtonFormField<String>(initialValue: supplier, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Nhà cung cấp'), items: [
            const DropdownMenuItem(value: null, child: Text('Không ghi nhận NCC')),
            ...widget.suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text('${s.name}${s.phone.isEmpty ? '' : ' • ${s.phone}'}')))],
          onChanged: busy ? null : (v) => setState(() => supplier = v)),
        TextFormField(controller: external, enabled: !busy, maxLength: 200, decoration: const InputDecoration(labelText: 'Số hóa đơn / chứng từ ngoài')),
        TextFormField(controller: note, enabled: !busy, maxLength: 2000, maxLines: 2,
          decoration: InputDecoration(labelText: widget.kind == StockDocumentKind.receipt ? 'Ghi chú' : 'Lý do xuất / kiểm kê'),
          validator: (v) => widget.kind != StockDocumentKind.receipt && (v == null || v.trim().isEmpty) ? 'Nhập lý do' : null),
        const Divider(),
        for (var i = 0; i < lines.length; i++) _line(i),
        TextButton.icon(onPressed: busy || lines.length >= 200 ? null : () => setState(() => lines.add(_StockLineEditor(null, 1, 0))),
          icon: const Icon(Icons.add), label: const Text('Thêm dòng')),
        Text('Tổng giá trị: ${stockMoney(total)}', key: const Key('stock-draft-total'), style: const TextStyle(fontWeight: FontWeight.bold)),
        const Text('Lưu nháp chưa thay đổi tồn. Xác nhận ghi kho ở màn hình chi tiết.'),
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]))),
    actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Quay lại')),
      FilledButton(key: const Key('stock-save-draft'), onPressed: busy ? null : save, child: Text(busy ? 'Đang lưu…' : 'Lưu nháp'))]));
  Widget _line(int i) {
    final l = lines[i];
    final product = widget.products.where((p) => p.id == l.productId).firstOrNull;
    return Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(children: [
      DropdownButtonFormField<String>(key: ValueKey(l), initialValue: l.productId, isExpanded: true,
        decoration: InputDecoration(labelText: 'Sản phẩm dòng ${i + 1}'),
        items: widget.products.where((p) => p.id == l.productId || !lines.any((other) => other.productId == p.id))
          .map((p) => DropdownMenuItem(value: p.id, child: Text('${p.name} • ${p.unitName.isEmpty ? 'Chưa thiết lập đơn vị' : p.unitName}', overflow: TextOverflow.ellipsis))).toList(),
        onChanged: busy ? null : (v) => setState(() => l.productId = v),
        validator: (v) => v == null ? 'Chọn sản phẩm' : null),
      if (product != null) Text('Tồn hiện tại: ${product.stockOnHand} • ${product.stockLabel}',
        style: TextStyle(color: product.isNegativeStock ? Colors.redAccent : null)),
      Row(children: [
        Expanded(child: TextFormField(controller: l.quantity, enabled: !busy, keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: widget.kind == StockDocumentKind.adjustment ? 'Tồn thực tế' : 'Số lượng'),
          onChanged: (_) => setState(() {}), validator: (v) {
            final q = int.tryParse(v ?? '');
            return q == null || q > 1000000 || (widget.kind == StockDocumentKind.adjustment ? q < 0 : q <= 0) ? 'Số lượng không hợp lệ' : null;
          })),
        if (widget.kind == StockDocumentKind.receipt) ...[
          const SizedBox(width: 8), Expanded(child: TextFormField(controller: l.cost, enabled: !busy,
            keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Giá nhập / đơn vị (đ)'),
            onChanged: (_) => setState(() {}), validator: (v) { final c = int.tryParse(v ?? ''); return c == null || c < 0 || c > 1000000000 ? 'Giá không hợp lệ' : null; })),
        ],
        IconButton(onPressed: busy || lines.length == 1 ? null : () { setState(() => lines.removeAt(i)); WidgetsBinding.instance.addPostFrameCallback((_) => l.dispose()); },
          tooltip: 'Xóa dòng nháp', icon: const Icon(Icons.delete_outline)),
      ]),
      if (widget.kind == StockDocumentKind.receipt) Align(alignment: Alignment.centerRight,
        child: Text('Thành tiền: ${stockMoney((int.tryParse(l.quantity.text) ?? 0) * (int.tryParse(l.cost.text) ?? 0))}')),
    ])));
  }
}

class StockSuppliersPanel extends ConsumerWidget {
  const StockSuppliersPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(appDataBackendProvider) == AppDataBackend.fake) { return const Center(child: Text('Nhà cung cấp cần chuyển sang dữ liệu salon.')); }
    return Column(children: [
      Align(alignment: Alignment.centerRight, child: FilledButton.icon(key: const Key('stock-new-supplier'),
        onPressed: () => _edit(context, ref), icon: const Icon(Icons.add_business), label: const Text('Thêm nhà cung cấp'))),
      Expanded(child: ref.watch(stockSuppliersProvider).when(loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text('Không tải được NCC: $e'), data: (items) => ListView(children: [
          for (final s in items) ListTile(title: Text(s.name), subtitle: Text('${s.phone} • ${s.email}\n${s.address} • ${s.isActive ? 'Đang sử dụng' : 'Ngừng sử dụng'}'),
            isThreeLine: true, onTap: () => _edit(context, ref, s),
            trailing: IconButton(tooltip: s.isActive ? 'Ngừng sử dụng' : 'Bật lại', icon: Icon(s.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline),
              onPressed: () async {
                if (!await ensureSensitiveActionAuthorized(context, ref, SensitiveAction.stockDocument) || !context.mounted) { return; }
                final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(s.isActive ? 'Ngừng sử dụng ${s.name}?' : 'Bật lại ${s.name}?'),
                  content: const Text('Chứng từ lịch sử vẫn giữ nguyên.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Quay lại')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Xác nhận'))]));
                if (ok != true || !context.mounted) { return; }
                try {
                  await ref.read(stockDocumentRepositoryProvider).saveSupplier(StockSupplier(id: s.id, name: s.name, phone: s.phone,
                    email: s.email, address: s.address, note: s.note, isActive: !s.isActive));
                  if (context.mounted) { refreshStockDocuments(ref); }
                } catch (e) { if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } }
              })),
        ]))),
    ]);
  }
  Future<void> _edit(BuildContext context, WidgetRef ref, [StockSupplier? existing]) async {
    if (!await ensureSensitiveActionAuthorized(context, ref, SensitiveAction.stockDocument) || !context.mounted) { return; }
    final names = ['Tên nhà cung cấp', 'Điện thoại', 'Email', 'Địa chỉ', 'Ghi chú'];
    final initial = [existing?.name ?? '', existing?.phone ?? '', existing?.email ?? '', existing?.address ?? '', existing?.note ?? ''];
    final controllers = initial.map((v) => TextEditingController(text: v)).toList();
    final id = existing?.id ?? EntityId.create('supplier');
    bool busy = false;
    String? error;
    final form = GlobalKey<FormState>();
    await showDialog<void>(context: context, barrierDismissible: false, builder: (dialogContext) => StatefulBuilder(builder: (_, update) => PopScope(
      canPop: !busy, child: AlertDialog(title: Text(existing == null ? 'Thêm nhà cung cấp' : 'Sửa nhà cung cấp'),
        content: SizedBox(width: 480, child: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < controllers.length; i++) TextFormField(controller: controllers[i], enabled: !busy,
            maxLength: i == 0 ? 200 : 2000, decoration: InputDecoration(labelText: names[i]),
            validator: i == 0 ? (v) => v == null || v.trim().isEmpty ? 'Nhập tên NCC' : null : null),
          if (error != null) Text(error!),
        ])))),
        actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(dialogContext), child: const Text('Quay lại')),
          FilledButton(onPressed: busy ? null : () async {
            if (busy || !form.currentState!.validate()) { return; }
            update(() { busy = true; error = null; });
            try {
              await ref.read(stockDocumentRepositoryProvider).saveSupplier(StockSupplier(id: id, name: controllers[0].text,
                phone: controllers[1].text, email: controllers[2].text, address: controllers[3].text, note: controllers[4].text,
                isActive: existing?.isActive ?? true));
              if (context.mounted) { refreshStockDocuments(ref); }
              if (dialogContext.mounted) { Navigator.pop(dialogContext); }
            } catch (e) { if (dialogContext.mounted) { update(() { busy = false; error = '$e'; }); } }
          }, child: Text(busy ? 'Đang lưu…' : 'Lưu'))]))));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final c in controllers) { c.dispose(); }
  }
}
 
class StockMovementHistoryPage extends ConsumerStatefulWidget {
  const StockMovementHistoryPage({super.key});
  @override
  ConsumerState<StockMovementHistoryPage> createState() => _StockMovementHistoryPageState();
}
class _StockMovementHistoryPageState extends ConsumerState<StockMovementHistoryPage> {
  String query = '', source = 'all';
  int offset = 0;
  DateTime? from, to;
  Future<List<InventoryMovementItem>>? future;
  final search = TextEditingController();
  void reload() => setState(() => future = ref.read(stockDocumentRepositoryProvider)
    .movementHistory(query: query, source: source, from: from, to: to, offset: offset));
  @override
  void dispose() { search.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (ref.watch(appDataBackendProvider) == AppDataBackend.fake) { return const Center(child: Text('Lịch sử chứng từ cần chuyển sang dữ liệu salon.')); }
    ref.listen(stockDocumentsNonceProvider, (_, next) => reload());
    future ??= ref.read(stockDocumentRepositoryProvider).movementHistory();
    return Column(children: [
      TextField(controller: search, onSubmitted: (v) { query = v; offset = 0; reload(); },
        decoration: InputDecoration(labelText: 'Tìm mã phiếu / bút toán / sản phẩm', isDense: true,
          suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () { query = search.text; offset = 0; reload(); }))),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(width: 220, child: DropdownButtonFormField<String>(initialValue: source,
          decoration: const InputDecoration(isDense: true, labelText: 'Nguồn giao dịch'),
          items: const [DropdownMenuItem(value: 'all', child: Text('Tất cả')), DropdownMenuItem(value: 'document', child: Text('Chứng từ kho')),
            DropdownMenuItem(value: 'sale', child: Text('Bán / hủy hóa đơn')), DropdownMenuItem(value: 'legacy', child: Text('Lịch sử cũ (legacy)'))],
          onChanged: (v) { source = v ?? 'all'; offset = 0; reload(); })),
        TextButton(onPressed: () => _date(true), child: Text(from == null ? 'Từ ngày' : DateFormat('dd/MM/yyyy').format(from!))),
        TextButton(onPressed: () => _date(false), child: Text(to == null ? 'Đến ngày' : DateFormat('dd/MM/yyyy').format(to!))),
        TextButton(onPressed: () { from = null; to = null; offset = 0; reload(); }, child: const Text('Xóa lọc ngày')),
      ]),
      Expanded(child: FutureBuilder<List<InventoryMovementItem>>(future: future, builder: (context, snapshot) {
        if (snapshot.hasError) { return Center(child: TextButton(onPressed: reload, child: Text('Tải lại: ${snapshot.error}'))); }
        if (snapshot.connectionState != ConnectionState.done) { return const Center(child: CircularProgressIndicator()); }
        final items = snapshot.data ?? [];
        return Column(children: [
          Expanded(child: items.isEmpty ? const Center(child: Text('Không có giao dịch phù hợp.')) : ListView.separated(
            itemCount: items.length, separatorBuilder: (_, _) => const Divider(height: 1), itemBuilder: (_, i) {
              final m = items[i];
              return ListTile(title: Text('${m.movementLabel} • ${m.productName}'),
                subtitle: Text('${m.sourceLabel}\n${DateFormat('dd/MM/yyyy HH:mm').format(m.createdAt)} • ${m.note}'),
                isThreeLine: true, trailing: Text('${m.stockBefore} → ${m.stockAfter}',
                  style: TextStyle(color: m.stockAfter < 0 ? Colors.redAccent : null)),
                onTap: m.documentId == null ? null : () async {
                  try {
                    final doc = await ref.read(stockDocumentRepositoryProvider).document(m.documentId!);
                    if (context.mounted) { await showStockDocument(context, ref, doc); }
                  } catch (e) { if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } }
                });
            })),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(onPressed: offset == 0 ? null : () { offset = (offset - 50).clamp(0, 1000000); reload(); }, child: const Text('Trang trước')),
            Text('Trang ${offset ~/ 50 + 1}'),
            TextButton(onPressed: items.length < 50 ? null : () { offset += 50; reload(); }, child: const Text('Trang sau')),
          ]),
        ]);
      })),
    ]);
  }
  Future<void> _date(bool start) async {
    final value = await showDatePicker(context: context, initialDate: (start ? from : to) ?? DateTime.now(),
      firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (value == null || !mounted) { return; }
    if (start) { from = value; } else { to = value; }
    offset = 0; reload();
  }
}
