import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/catalog_option.dart';
import '../../core/providers/catalog_options_providers.dart';

class CatalogOptionPicker extends ConsumerWidget {
  const CatalogOptionPicker({
    super.key,
    required this.kind,
    required this.labelText,
    required this.value,
    required this.onChanged,
    this.allowEmpty = false,
    this.emptyLabel = 'Không chọn',
  });

  final CatalogOptionKind kind;
  final String labelText;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowEmpty;
  final String emptyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optionsState = ref.watch(catalogOptionNamesProvider(kind));
    final options = [...(optionsState.value ?? kind.defaultNames)];
    final current = normalizeCatalogOptionName(value ?? '');
    if (current.isNotEmpty &&
        !options.any((item) => item.toLowerCase() == current.toLowerCase())) {
      options.add(current);
    }

    String? effectiveValue;
    if (current.isNotEmpty) {
      for (final option in options) {
        if (option.toLowerCase() == current.toLowerCase()) {
          effectiveValue = option;
          break;
        }
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            key: ValueKey(
              '${kind.databaseValue}:${effectiveValue ?? ''}:${options.join('|')}',
            ),
            initialValue: effectiveValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: labelText,
              helperText: optionsState.isLoading ? 'Đang tải danh mục…' : null,
            ),
            validator: (selected) {
              if (!allowEmpty && (selected == null || selected.trim().isEmpty)) {
                return 'Chọn $labelText';
              }
              return null;
            },
            items: [
              if (allowEmpty)
                DropdownMenuItem<String?>(value: null, child: Text(emptyLabel)),
              ...options.map(
                (item) => DropdownMenuItem<String?>(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: IconButton.outlined(
            tooltip: 'Tạo ${kind.displayLabel}',
            onPressed: () => _createOption(context, ref),
            icon: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }

  Future<void> _createOption(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _CreateCatalogOptionDialog(kind: kind),
    );
    if (name == null || !context.mounted) return;

    try {
      final saved = await ref
          .read(catalogOptionsRepositoryProvider)
          .createOption(kind, name);
      if (!context.mounted) return;
      ref.read(catalogOptionsRefreshNonceProvider.notifier).state++;
      onChanged(saved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã tạo ${kind.displayLabel} “$saved”')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không tạo được ${kind.displayLabel}: $error')),
      );
    }
  }
}

class _CreateCatalogOptionDialog extends StatefulWidget {
  const _CreateCatalogOptionDialog({required this.kind});

  final CatalogOptionKind kind;

  @override
  State<_CreateCatalogOptionDialog> createState() =>
      _CreateCatalogOptionDialogState();
}

class _CreateCatalogOptionDialogState extends State<_CreateCatalogOptionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Tạo ${widget.kind.displayLabel}'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên'),
          textInputAction: TextInputAction.done,
          validator: (value) => normalizeCatalogOptionName(value ?? '').isEmpty
              ? 'Nhập tên'
              : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Tạo')),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(normalizeCatalogOptionName(_controller.text));
  }
}
