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
# Keep the checkout column fully visible at the 1280x720 regression size
# without reintroducing an inner scrollbar for the normal desktop layout.
text = text.replace('SizedBox(height: dense ? 9 : 11)', 'SizedBox(height: dense ? 6 : 11)')
text = text.replace('SizedBox(height: dense ? 9 : 12)', 'SizedBox(height: dense ? 6 : 12)')
text = text.replace('const SizedBox(height: 7),\n          _CheckoutQuickActions(', 'const SizedBox(height: 4),\n          _CheckoutQuickActions(', 1)
path.write_text(text)
