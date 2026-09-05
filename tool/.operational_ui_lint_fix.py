from pathlib import Path

path = Path('lib/features/invoices/presentation/pages/pos_checkout_panel.dart')
text = path.read_text()
start = text.index('class _AmountLine extends StatelessWidget {')
end = text.index('class _PaymentMethodSelector extends StatelessWidget {', start)
replacement = r'''class _AmountLine extends StatelessWidget {
  const _AmountLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

'''
text = text[:start] + replacement + text[end:]

# Keep the checkout column fully visible at small desktop sizes without
# reintroducing an inner scrollbar.
text = text.replace('SizedBox(height: dense ? 9 : 11)', 'SizedBox(height: dense ? 6 : 11)')
text = text.replace('SizedBox(height: dense ? 9 : 12)', 'SizedBox(height: dense ? 4 : 12)')
text = text.replace(
    "const SizedBox(height: 7),\n          _PaymentMethodSelector(",
    "SizedBox(height: dense ? 4 : 7),\n          _PaymentMethodSelector(",
    1,
)
text = text.replace(
    "const SizedBox(height: 7),\n          _CheckoutQuickActions(",
    "const SizedBox(height: 4),\n          _CheckoutQuickActions(",
    1,
)
text = text.replace(
    """          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(""",
    """          SizedBox(
            width: double.infinity,
            height: dense ? 38 : 44,
            child: FilledButton.icon(""",
    1,
)

# At the 1024 desktop regression size the checkout column is ~254px wide.
# Keep the three payment choices on one line; preserve the full label in a
# tooltip rather than allowing “Chuyển khoản” to wrap and grow the row.
old = """        const gap = 6.0;
        final width = (constraints.maxWidth - gap * 2) / 3;
        return Row("""
new = """        const gap = 6.0;
        final width = (constraints.maxWidth - gap * 2) / 3;
        final compactLabels = constraints.maxWidth < 280;
        return Row("""
if old not in text:
    raise RuntimeError('payment selector width marker not found')
text = text.replace(old, new, 1)
old = """              child: AppChoiceButton(
                label: 'Chuyển khoản',
                selected: selected == 'Chuyển khoản',
                onTap: locked ? null : () => onSelected('Chuyển khoản'),
              ),"""
new = """              child: Tooltip(
                message: 'Chuyển khoản',
                child: AppChoiceButton(
                  label: compactLabels ? 'CK' : 'Chuyển khoản',
                  selected: selected == 'Chuyển khoản',
                  onTap: locked ? null : () => onSelected('Chuyển khoản'),
                ),
              ),"""
if old not in text:
    raise RuntimeError('payment selector transfer marker not found')
text = text.replace(old, new, 1)

# Keep the quick tools at the bottom as approved, but make them truly compact
# in dense layouts so the operational panel remains viewport-bound.
old = """          _CheckoutQuickActions(
            draft: draft,
            selectedCustomer: selectedCustomer,
          ),"""
new = """          _CheckoutQuickActions(
            draft: draft,
            selectedCustomer: selectedCustomer,
            dense: dense,
          ),"""
if old not in text:
    raise RuntimeError('quick action call marker not found')
text = text.replace(old, new, 1)
old = """  const _CheckoutQuickActions({
    required this.draft,
    required this.selectedCustomer,
  });"""
new = """  const _CheckoutQuickActions({
    required this.draft,
    required this.selectedCustomer,
    required this.dense,
  });"""
if old not in text:
    raise RuntimeError('quick action constructor marker not found')
text = text.replace(old, new, 1)
old = """  final InvoiceDraft draft;
  final CustomerProfile? selectedCustomer;

  @override
  Widget build(BuildContext context) {"""
new = """  final InvoiceDraft draft;
  final CustomerProfile? selectedCustomer;
  final bool dense;

  @override
  Widget build(BuildContext context) {"""
if old not in text:
    raise RuntimeError('quick action field marker not found')
text = text.replace(old, new, 1)

for icon_name in ['qr_code_2_outlined', 'picture_as_pdf_outlined']:
    old = f"""            icon: const Icon(Icons.{icon_name}, size: 18),"""
    new = f"""            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
              width: dense ? 30 : 40,
              height: dense ? 30 : 40,
            ),
            icon: const Icon(Icons.{icon_name}, size: 18),"""
    if old not in text:
        raise RuntimeError(f'quick action icon marker not found: {icon_name}')
    text = text.replace(old, new, 1)

path.write_text(text)