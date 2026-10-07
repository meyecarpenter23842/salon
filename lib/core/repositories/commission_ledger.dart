import 'package:sqflite/sqflite.dart';
import 'invoice_revenue_allocation.dart';

/// Money is integer VND; rates are basis points (0.01%). Round per archived line.
class CommissionLedger {
  static String month(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  static int rateBps(Object? stored) {
    final rate = stored is num ? stored.toDouble() : double.tryParse('$stored');
    if (rate == null || !rate.isFinite || rate < 0 || rate > 1) {
      throw StateError('Tỷ lệ hoa hồng không hợp lệ. Sửa hồ sơ nhân viên (0–100%).');
    }
    return (rate * 10000).round();
  }

  static Future<String> _openMonth(DatabaseExecutor db, DateTime date) async {
    var candidate = DateTime(date.year, date.month);
    while ((await db.query('commission_periods', where: 'period=?',
        whereArgs: [month(candidate)], limit: 1)).isNotEmpty) {
      candidate = DateTime(candidate.year, candidate.month + 1);
    }
    return month(candidate);
  }

  /// Called inside the same transaction as archive/stock/payment, including LAN.
  static Future<void> capture(DatabaseExecutor db, String invoiceId, DateTime now) async {
    final invoice = (await db.query('invoices', where: 'id=? AND paid_at IS NOT NULL',
      whereArgs: [invoiceId], limit: 1)).single;
    final rows = await db.query('invoice_items', where: 'invoice_id=?',
      whereArgs: [invoiceId], orderBy: 'id');
    final benefitRows = await db.query(
      'invoice_benefit_line_snapshots',
      where: 'invoice_id=?',
      whereArgs: [invoiceId],
    );
    final benefitByLine = <String, Map<String, Object?>>{
      for (final row in benefitRows) row['invoice_line_id'] as String: row,
    };
    final allocated = benefitRows.isEmpty
        ? allocateInvoiceNetRevenue(
            invoiceTotal: invoice['total_amount'] as int,
            lines: rows.map((r) => RevenueAllocationInput(
              id: r['id'] as String,
              amount: r['total_price'] as int,
            )).toList(),
          )
        : const <String, int>{};
    if (benefitRows.isNotEmpty && benefitByLine.length != rows.length) {
      throw StateError('Snapshot quyền lợi không đủ dòng để tính hoa hồng.');
    }
    final period = await _openMonth(db, now);
    for (final row in rows) {
      if (row['item_type'] != 'service' || row['employee_id'] == null) continue;
      final employee = await db.query('employees', where: 'id=?',
        whereArgs: [row['employee_id']], limit: 1);
      if (employee.isEmpty) throw StateError('Nhân viên dịch vụ không còn tồn tại.');
      final bps = rateBps(employee.single['commission_rate']);
      final lineId = row['id'] as String;
      final benefitLine = benefitByLine[lineId];
      final basis = benefitLine == null
          ? (allocated[lineId] ?? 0)
          : (benefitLine['cash_basis'] as int) +
              (benefitLine['recognized_value'] as int);
      final id = 'commission-earned-${row['id']}';
      // A replay must never recalculate with a new employee rate.
      if ((await db.query('commission_entries', where: 'id=?', whereArgs: [id])).isNotEmpty) continue;
      await db.insert('commission_entries', {
        'id': id, 'invoice_id': invoiceId, 'line_id': row['id'],
        'employee_id': row['employee_id'], 'employee_name': employee.single['full_name'],
        'title': row['title'], 'kind': 'earned', 'original_id': null, 'period': period,
        'rate_bps': bps, 'basis': basis, 'amount': (basis * bps + 5000) ~/ 10000,
        'created_at': now.toIso8601String(),
      });
    }
  }

  /// Full refund/void uses original money/rate, in the month AFTER adjustment.
  static Future<void> reverse(DatabaseExecutor db, String invoiceId, DateTime now) async {
    final originals = await db.query('commission_entries',
      where: "invoice_id=? AND kind='earned'", whereArgs: [invoiceId]);
    for (final row in originals) {
      var next = DateTime(now.year, now.month + 1);
      final originalMonth = DateTime.parse('${row['period']}-01');
      final afterOriginal = DateTime(originalMonth.year, originalMonth.month + 1);
      if (next.isBefore(afterOriginal)) next = afterOriginal;
      final period = await _openMonth(db, next);
      final id = 'commission-reversal-${row['line_id']}';
      if ((await db.query('commission_entries', where: 'id=?', whereArgs: [id])).isNotEmpty) continue;
      await db.insert('commission_entries', {
        ...row, 'id': id, 'kind': 'reversal', 'original_id': row['id'],
        'period': period, 'amount': -(row['amount'] as int),
        'created_at': now.toIso8601String(),
      });
    }
  }
}
