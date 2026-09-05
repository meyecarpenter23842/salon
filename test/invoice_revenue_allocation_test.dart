import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/repositories/invoice_revenue_allocation.dart';

void main() {
  test('allocateInvoiceNetRevenue preserves invoice net with integer remainder', () {
    final allocation = allocateInvoiceNetRevenue(
      invoiceTotal: 99,
      lines: const [
        RevenueAllocationInput(id: 'a', amount: 50),
        RevenueAllocationInput(id: 'b', amount: 30),
        RevenueAllocationInput(id: 'c', amount: 20),
      ],
    );

    expect(allocation, const {'a': 49, 'b': 30, 'c': 20});
    expect(allocation.values.fold<int>(0, (sum, value) => sum + value), 99);
  });

  test('allocateInvoiceNetRevenue resolves equal remainders deterministically', () {
    final allocation = allocateInvoiceNetRevenue(
      invoiceTotal: 1,
      lines: const [
        RevenueAllocationInput(id: 'first', amount: 1),
        RevenueAllocationInput(id: 'second', amount: 1),
        RevenueAllocationInput(id: 'third', amount: 1),
      ],
    );

    expect(allocation, const {'first': 1, 'second': 0, 'third': 0});
  });
}
