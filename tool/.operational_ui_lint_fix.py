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
path.write_text(text[:start] + replacement + text[end:])
