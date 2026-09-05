import 'package:sqflite/sqflite.dart';

class RevenueAllocationInput {
  const RevenueAllocationInput({required this.id, required this.amount});

  final String id;
  final int amount;
}

class AllocatedInvoiceLine {
  const AllocatedInvoiceLine({
    required this.invoiceId,
    required this.lineId,
    required this.customerId,
    required this.itemType,
    required this.title,
    required this.quantity,
    required this.netRevenue,
    this.serviceId,
    this.productId,
    this.employeeId,
  });

  final String invoiceId;
  final String lineId;
  final String customerId;
  final String itemType;
  final String title;
  final int quantity;
  final int netRevenue;
  final String? serviceId;
  final String? productId;
  final String? employeeId;
}

Map<String, int> allocateInvoiceNetRevenue({
  required int invoiceTotal,
  required List<RevenueAllocationInput> lines,
}) {
  if (lines.isEmpty) return const <String, int>{};

  final target = invoiceTotal < 0 ? 0 : invoiceTotal;
  final weights = lines
      .map((line) => line.amount < 0 ? 0 : line.amount)
      .toList(growable: false);
  final totalWeight = weights.fold<int>(0, (sum, value) => sum + value);

  if (totalWeight == 0) {
    return <String, int>{
      for (var index = 0; index < lines.length; index++)
        lines[index].id: index == 0 ? target : 0,
    };
  }

  final allocations = List<int>.filled(lines.length, 0);
  final remainders = List<int>.filled(lines.length, 0);
  var allocated = 0;

  for (var index = 0; index < lines.length; index++) {
    final weighted = weights[index] * target;
    allocations[index] = weighted ~/ totalWeight;
    remainders[index] = weighted % totalWeight;
    allocated += allocations[index];
  }

  var remaining = target - allocated;
  final order = List<int>.generate(lines.length, (index) => index)
    ..sort((left, right) {
      final remainderCompare = remainders[right].compareTo(remainders[left]);
      return remainderCompare != 0 ? remainderCompare : left.compareTo(right);
    });

  var cursor = 0;
  while (remaining > 0) {
    allocations[order[cursor % order.length]] += 1;
    remaining -= 1;
    cursor += 1;
  }

  return <String, int>{
    for (var index = 0; index < lines.length; index++)
      lines[index].id: allocations[index],
  };
}

Future<List<AllocatedInvoiceLine>> loadAllocatedInvoiceLines(
  DatabaseExecutor database, {
  required DateTime start,
  required DateTime end,
}) async {
  final rows = await database.rawQuery(
    'SELECT i.id AS invoice_id, i.customer_id, i.total_amount AS invoice_total, '
    'ii.id AS line_id, ii.item_type, ii.service_id, ii.product_id, '
    'ii.employee_id, ii.title, ii.quantity, ii.total_price AS line_total '
    'FROM invoices i '
    'JOIN invoice_items ii ON ii.invoice_id = i.id '
    'WHERE i.paid_at IS NOT NULL AND i.paid_at >= ? AND i.paid_at < ? '
    'ORDER BY i.id ASC, ii.id ASC',
    [start.toIso8601String(), end.toIso8601String()],
  );

  if (rows.isEmpty) return const <AllocatedInvoiceLine>[];

  final rowsByInvoice = <String, List<Map<String, Object?>>>{};
  for (final row in rows) {
    final invoiceId = row['invoice_id']?.toString() ?? '';
    if (invoiceId.isEmpty) continue;
    rowsByInvoice.putIfAbsent(invoiceId, () => <Map<String, Object?>>[]).add(row);
  }

  final result = <AllocatedInvoiceLine>[];
  for (final entry in rowsByInvoice.entries) {
    final invoiceRows = entry.value;
    if (invoiceRows.isEmpty) continue;

    final allocations = allocateInvoiceNetRevenue(
      invoiceTotal: _toInt(invoiceRows.first['invoice_total']),
      lines: invoiceRows
          .map(
            (row) => RevenueAllocationInput(
              id: row['line_id']?.toString() ?? '',
              amount: _toInt(row['line_total']),
            ),
          )
          .toList(growable: false),
    );

    for (final row in invoiceRows) {
      final lineId = row['line_id']?.toString() ?? '';
      result.add(
        AllocatedInvoiceLine(
          invoiceId: entry.key,
          lineId: lineId,
          customerId: row['customer_id']?.toString() ?? '',
          itemType: row['item_type']?.toString() ?? '',
          title: row['title']?.toString() ?? '',
          quantity: _toInt(row['quantity']),
          netRevenue: allocations[lineId] ?? 0,
          serviceId: _nullableId(row['service_id']),
          productId: _nullableId(row['product_id']),
          employeeId: _nullableId(row['employee_id']),
        ),
      );
    }
  }

  return result;
}

String? _nullableId(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
