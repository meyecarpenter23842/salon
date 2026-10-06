import 'package:flutter/material.dart';
import '../../core/lan/lan_contract.dart';
import '../../core/lan/lan_health_client.dart';
import '../../core/lan/lan_pairing.dart';
import '../../core/lan/lan_workflow_client.dart';
import '../../core/lan/lan_workflow_models.dart';
import 'companion_mobile_list.dart';

/// Server search/pagination preserves IDs, including selections on other pages.
class CompanionCatalogPicker extends StatefulWidget {
  const CompanionCatalogPicker({super.key, required this.connection, required this.token,
    required this.client, required this.kind, required this.epoch, required this.onDenied,
    this.selected = const {}, this.multiple = false});
  final LanConnection connection;
  final String token, kind, epoch;
  final LanWorkflowClient client;
  final VoidCallback onDenied;
  final Map<String, String> selected;
  final bool multiple;
  @override State<CompanionCatalogPicker> createState() => _CompanionCatalogPickerState();
}
class _CompanionCatalogPickerState extends State<CompanionCatalogPicker> {
  final search = TextEditingController();
  late final Map<String, String> selected = Map.of(widget.selected);
  List<LanCatalogItem> rows = [];
  String query = '';
  MobileReadProblem? error;
  int generation = 0;
  int? next;
  bool busy = false;
  String get title => switch(widget.kind) {
    'customers' => 'Chọn khách hàng', 'services' => 'Chọn dịch vụ', _ => 'Chọn nhân viên',
  };
  @override void initState() { super.initState(); _load(); }
  Future<void> _load({int offset = 0}) async {
    final current = ++generation;
    setState(() { busy = true; error = null; });
    try {
      final page = await widget.client.catalog(widget.connection, widget.token, widget.kind, query, offset);
      if (!mounted || current != generation) { return; }
      if (page.epoch != widget.epoch) {
        setState(() { busy = false; rows = []; error = const MobileReadProblem(Icons.refresh, 'Cần tải lại biểu mẫu', 'Máy salon đã khởi động lại. Quay lại và tải lại biểu mẫu trước khi chọn.'); });
        return;
      }
      setState(() { rows = offset == 0 ? page.items : [...rows, ...page.items]; next = page.nextOffset; busy = false; });
    } catch(e) {
      if (!mounted || current != generation) { return; }
      setState(() { busy = false; rows = []; error = MobileReadProblem.from(e); });
      if (e is PairingFailure && [LanErrorCode.forbidden, LanErrorCode.unauthenticated].contains(e.code)) { widget.onDenied(); }
    }
  }
  void _choose(LanCatalogItem item) {
    if (!widget.multiple) { Navigator.of(context).pop(<String, String>{item.id: item.title}); return; }
    if (!selected.containsKey(item.id) && selected.length >= 20) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mỗi lịch hẹn chọn tối đa 20 dịch vụ.')));
      return;
    }
    setState(() { if (selected.containsKey(item.id)) { selected.remove(item.id); } else { selected[item.id] = item.title; } });
  }
  @override void dispose() { generation++; search.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(key: const Key('mobile-picker-search'),
        controller: search, maxLength: 80, textInputAction: TextInputAction.search,
        decoration: InputDecoration(hintText: widget.kind == 'customers' ? 'Tên hoặc số điện thoại' : 'Tìm theo tên',
          counterText: '', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(key: const Key('mobile-picker-find'),
            onPressed: () { query = search.text.trim(); FocusManager.instance.primaryFocus?.unfocus(); _load(); },
            icon: const Icon(Icons.arrow_forward))),
        onSubmitted: (value) { query = value.trim(); _load(); })),
      if (busy) const LinearProgressIndicator(),
      Expanded(child: error != null ? MobileStatus(icon: error!.icon, title: error!.title,
          message: error!.message, action: 'Thử lại', onAction: _load)
        : !busy && rows.isEmpty ? MobileStatus(icon: Icons.search_off, title: 'Chưa tìm thấy',
          message: 'Thử tên khác hoặc kiểm tra danh mục trên máy salon.', action: 'Tải lại', onAction: _load)
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: rows.length + 1,
          itemBuilder: (context, index) {
            if (index == rows.length) { return next == null ? const SizedBox(height: 24) :
              TextButton(key: const Key('mobile-picker-next'), onPressed: busy ? null : () => _load(offset: next!), child: const Text('Xem thêm')); }
            final item = rows[index];
            return Card(child: ListTile(key: Key('mobile-pick-${item.id}'), title: Text(item.title),
              subtitle: Text(item.subtitle), onTap: () => _choose(item),
              trailing: widget.multiple ? Icon(selected.containsKey(item.id) ? Icons.check_circle : Icons.radio_button_unchecked) : const Icon(Icons.chevron_right)));
          })),
    ])),
    bottomNavigationBar: widget.multiple ? SafeArea(child: Padding(padding: const EdgeInsets.all(16),
      child: FilledButton(key: const Key('mobile-picker-done'), onPressed: () => Navigator.of(context).pop(Map<String, String>.of(selected)),
        child: Text('Chọn ${selected.length} dịch vụ')))) : null,
  );
}
