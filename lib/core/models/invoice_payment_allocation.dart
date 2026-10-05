class InvoicePaymentAllocation {
  const InvoicePaymentAllocation({
    required this.paymentMethod,
    required this.amount,
  });

  final String paymentMethod;
  final int amount;
}
