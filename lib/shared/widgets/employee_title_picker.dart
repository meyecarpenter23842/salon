import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/catalog_option.dart';
import '../../core/models/audit_event.dart';
import '../../core/providers/catalog_options_providers.dart';
import 'sensitive_action_authorization.dart';

class EmployeeTitlePicker extends ConsumerWidget {
  const EmployeeTitlePicker({
    super.key,
    required this.name,
    required this.id,
    required this.onChanged,
  });
  final String name;
  final String? id;
  final void Function(String, String?) onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      catalogOptionsProvider(CatalogOptionKind.employeeTitle),
    );
    final options = state.value ?? const <CatalogOption>[];
    final selected = options
        .where(
          (o) => id != null
              ? o.id == id
              : catalogNameKey(o.name) == catalogNameKey(name),
        )
        .firstOrNull;
    if (id == null && selected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          onChanged(name, selected.id);
        }
      });
    }
    final visible = options
        .where((o) => o.isActive || o.id == selected?.id)
        .toList();
    if (selected == null && name.isNotEmpty) {
      visible.add(
        CatalogOption(
          id: 'legacy-retained',
          kind: CatalogOptionKind.employeeTitle,
          name: name,
          isActive: false,
        ),
      );
    }
    final value = selected?.id ?? (name.isNotEmpty ? 'legacy-retained' : null);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(
              'title:$value:${visible.map((o) => o.id + o.name + o.isActive.toString()).join('|')}',
            ),
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Chức danh',
              helperText: state.isLoading
                  ? 'Đang tải chức danh…'
                  : state.hasError
                  ? 'Không tải được. Mở lại để thử lại.'
                  : selected?.isActive == false ||
                        selected == null && name.isNotEmpty
                  ? 'Giữ chức danh cũ; không dùng cho hồ sơ mới.'
                  : null,
              helperMaxLines: 2,
            ),
            items: visible
                .map(
                  (o) => DropdownMenuItem(
                    value: o.id,
                    child: Text(o.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            validator: (_) => state.isLoading || state.hasError
                ? 'Chờ tải danh mục chức danh.'
                : name.trim().isEmpty
                ? 'Chọn chức danh'
                : null,
            onChanged: state.isLoading || state.hasError
                ? null
                : (value) {
                    final option = visible.singleWhere((o) => o.id == value);
                    onChanged(
                      option.name,
                      option.id == 'legacy-retained' ? null : option.id,
                    );
                  },
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          tooltip: 'Thêm chức danh',
          icon: const Icon(Icons.add),
          onPressed: () async {
            if (!await ensureSensitiveActionAuthorized(
                  context,
                  ref,
                  SensitiveAction.settingsEdit,
                ) ||
                !context.mounted) {
              return;
            }
            final controller = TextEditingController();
            final input = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Thêm chức danh'),
                content: TextField(
                  controller: controller,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Tên chức danh'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Hủy'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, controller.text),
                    child: const Text('Thêm'),
                  ),
                ],
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 300));
            controller.dispose();
            if (input == null || !context.mounted) {
              return;
            }
            try {
              final repo = ref.read(catalogOptionsRepositoryProvider);
              final saved = await repo.createOption(
                CatalogOptionKind.employeeTitle,
                input,
              );
              final rows = await repo.fetchOptions(
                CatalogOptionKind.employeeTitle,
              );
              if (!context.mounted) {
                return;
              }
              ref.read(catalogOptionsRefreshNonceProvider.notifier).state++;
              final option = rows.singleWhere(
                (o) => catalogNameKey(o.name) == catalogNameKey(saved),
              );
              onChanged(option.name, option.id);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Không thêm được chức danh: $e')),
                );
              }
            }
          },
        ),
      ],
    );
  }
}

