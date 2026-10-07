import '../../core/models/audit_event.dart';
import 'sensitive_action_authorization.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/catalog_option.dart';
import '../../core/providers/catalog_options_providers.dart';

class CatalogManagementTabs extends StatelessWidget {
  const CatalogManagementTabs({super.key, required this.child, required this.kinds,
    this.listLabel = 'Danh sách'});
  final Widget child;
  final List<CatalogOptionKind> kinds;
  final String listLabel;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2, child: Column(children: [
      TabBar(tabs: [Tab(text: listLabel), const Tab(text: 'Thiết lập')]),
      const SizedBox(height: 12),
      Expanded(child: TabBarView(children: [
        child, CatalogSettingsPanel(kinds: kinds),
      ])),
    ]));
}

class CatalogSettingsPanel extends ConsumerStatefulWidget {
  const CatalogSettingsPanel({super.key, required this.kinds});
  final List<CatalogOptionKind> kinds;
  @override
  ConsumerState<CatalogSettingsPanel> createState() => _CatalogSettingsPanelState();
}

class _CatalogSettingsPanelState extends ConsumerState<CatalogSettingsPanel> {
  late CatalogOptionKind _kind;
  String _query = '';
  bool _showInactive = false;
  bool _busy = false;
  @override
  void initState() { super.initState(); _kind = widget.kinds.first; }

  Future<void> _edit([CatalogOption? item]) async {
    if(_kind==CatalogOptionKind.employeeTitle &&
      (!await ensureSensitiveActionAuthorized(context,ref,SensitiveAction.settingsEdit)||!mounted)) {return;}
    final controller = TextEditingController(text: item?.name ?? '');
    String? error;
    bool saving = false;
    final kind = _kind;
    await showDialog<void>(context: context, barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) {
        Future<void> save() async {
          if (saving) return;
          setDialogState(() { saving = true; error = null; });
          try {
            final repo = ref.read(catalogOptionsRepositoryProvider);
            if (item == null) { await repo.createOption(kind, controller.text); }
            else { await repo.renameOption(item.id, controller.text); }
            if (!mounted) return;
            ref.read(catalogOptionsRefreshNonceProvider.notifier).state++;
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          } catch (e) {
            if (dialogContext.mounted) setDialogState(() { saving = false; error = e.toString(); });
          }
        }
        return PopScope(canPop: !saving, child: AlertDialog(
          title: Text('${item == null ? 'Thêm' : 'Đổi tên'} ${kind.displayLabel}'),
          content: SizedBox(width: 380, child: TextField(
            controller: controller, autofocus: true, maxLength: 100, enabled: !saving,
            decoration: InputDecoration(labelText: 'Tên', errorText: error, errorMaxLines: 3),
            onSubmitted: (_) => save())),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Hủy')),
            FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Đang lưu…' : 'Lưu')),
          ]));
      }));
    // The dialog route may still be animating out when its future completes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  Future<void> _toggle(CatalogOption item) async {
    if(item.kind==CatalogOptionKind.employeeTitle &&
      (!await ensureSensitiveActionAuthorized(context,ref,SensitiveAction.settingsEdit)||!mounted)) {return;}
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(item.isActive ? 'Ngừng sử dụng “${item.name}”?' : 'Bật lại “${item.name}”?'),
      content: Text(item.isActive
        ? 'Dữ liệu đang dùng vẫn được giữ. Mục này sẽ không xuất hiện trong lựa chọn mới.'
        : 'Mục này sẽ xuất hiện lại trong danh sách lựa chọn.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận')),
      ]));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(catalogOptionsRepositoryProvider).setOptionActive(item.id, !item.isActive);
      if (mounted) ref.read(catalogOptionsRefreshNonceProvider.notifier).state++;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không lưu được: $e')));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(catalogOptionsProvider(_kind));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Thiết lập danh mục', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Danh mục dùng chung trong salon. Ngừng sử dụng vẫn giữ dữ liệu và lịch sử.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final kind in widget.kinds) ChoiceChip(label: Text(_title(kind)),
          selected: kind == _kind, onSelected: _busy ? null : (_) => setState(() { _kind = kind; _query = ''; })),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        IconButton(tooltip:'Tải lại danh mục',onPressed:_busy?null:(){
          ref.read(catalogOptionsRefreshNonceProvider.notifier).state++;
        },icon:const Icon(Icons.refresh)),
        SizedBox(width: 260, child: TextField(key: ValueKey(_kind),
          decoration: const InputDecoration(labelText: 'Tìm danh mục', prefixIcon: Icon(Icons.search)),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()))),
        FilterChip(label: const Text('Hiện mục ngừng sử dụng'), selected: _showInactive,
          onSelected: (v) => setState(() => _showInactive = v)),
        FilledButton.icon(onPressed: _busy ? null : () => _edit(),
          icon: const Icon(Icons.add), label: Text('Thêm ${_kind.displayLabel}')),
      ]),
      if (_kind == CatalogOptionKind.productUnit) const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Đơn vị đếm tồn: chai, hộp, cái… Quy cách 500 ml vẫn nhập riêng trên sản phẩm.')),
      if(_kind==CatalogOptionKind.employeeTitle) const Padding(padding:EdgeInsets.symmetric(vertical:8),
        child:Text('Chức danh là vị trí công việc. Đổi tên cập nhật hồ sơ hiện tại; dữ liệu đã chốt giữ lịch sử. Không cấp quyền Owner hoặc điện thoại.')),
      const SizedBox(height: 8),
      if (_busy) const LinearProgressIndicator(),
      Expanded(child: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Không tải được danh mục: $e'),
          TextButton(onPressed: () => ref.invalidate(catalogOptionsProvider(_kind)), child: const Text('Thử lại')),
        ])),
        data: (items) {
          final visible = items.where((i) => (_showInactive || i.isActive) &&
            i.name.toLowerCase().contains(_query)).toList();
          if (visible.isEmpty) return const Center(child: Text('Chưa có danh mục phù hợp.'));
          return ListView.separated(itemCount: visible.length,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = visible[index];
              return ListTile(title: Text(item.name),
                subtitle: Text('${item.isActive ? 'Đang sử dụng' : 'Ngừng sử dụng'} · ${item.usageCount} bản ghi liên kết'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: 'Đổi tên', onPressed: _busy ? null : () => _edit(item), icon: const Icon(Icons.edit_outlined)),
                  IconButton(tooltip: item.isActive ? 'Ngừng sử dụng' : 'Bật lại',
                    onPressed: _busy ? null : () => _toggle(item),
                    icon: Icon(item.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline)),
                ]));
            });
        })),
    ]);
  }
}

String _title(CatalogOptionKind kind) => switch (kind) {
  CatalogOptionKind.productGroup => 'Nhóm sản phẩm',
  CatalogOptionKind.productBrand => 'Thương hiệu',
  CatalogOptionKind.serviceGroup => 'Nhóm dịch vụ',
  CatalogOptionKind.productUnit => 'Đơn vị tính',
  CatalogOptionKind.employeeTitle => 'Chức danh nhân viên',
};

Future<T?> saveCatalogRecord<T>(BuildContext context, Future<T> Function() save) async {
  try {
    return await save();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Chưa lưu được: $error'),
        duration: const Duration(seconds: 6),
      ));
    }
    return null;
  }
}
