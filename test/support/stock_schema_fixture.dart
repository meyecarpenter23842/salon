import 'package:sqflite/sqflite.dart';

// Reconstruct a real pre-20 file, preserving business rows.
Future<void> removeStockDocumentSchema(Database db) async {
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
