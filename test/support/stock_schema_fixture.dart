import 'package:sqflite/sqflite.dart';

// Reconstruct a real pre-20 file, preserving business rows.
Future<void> removeStockDocumentSchema(Database db) async {
  // Remove schema 21 too when reconstructing a pre-20 backup.
  for (final table in ['commission_payouts', 'commission_entries', 'commission_periods']) {
    await db.execute('DROP TABLE IF EXISTS $table');
  }
  await db.execute('DROP TRIGGER IF EXISTS commission_cash_no_update');
  await db.execute('DROP TRIGGER IF EXISTS commission_cash_no_delete');
  for (final name in ['stock_document_frozen', 'stock_document_no_delete', 'stock_line_no_update',
      'stock_line_no_delete', 'stock_line_no_insert', 'stock_movement_no_update', 'stock_movement_no_delete']) {
    await db.execute('DROP TRIGGER $name');
  }
  await db.execute('DROP INDEX idx_stock_movements_document');
  for (final column in ['document_id', 'document_line_id', 'source']) {
    await db.execute('ALTER TABLE inventory_movements DROP COLUMN $column');
  }
  await db.execute('DROP TABLE stock_document_lines');
  await db.execute('DROP TABLE stock_documents');
  await db.execute('DROP TABLE stock_suppliers');
}
