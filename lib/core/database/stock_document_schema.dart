import 'package:sqflite/sqflite.dart';

class StockDocumentSchema {
  static Future<void> install(DatabaseExecutor db) async {
    for (final sql in statements) { await db.execute(sql); }
  }
  static const statements = [
    """CREATE TABLE stock_suppliers (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, phone TEXT NOT NULL DEFAULT '',
      email TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '',
      is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)""",
    """CREATE TABLE stock_documents (
      sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE, number TEXT UNIQUE,
      kind TEXT NOT NULL CHECK(kind IN ('receipt','issue','adjustment')),
      status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','posted','cancelled')),
      document_date TEXT NOT NULL, supplier_id TEXT, supplier_name TEXT NOT NULL DEFAULT '',
      prepared_by TEXT NOT NULL, external_reference TEXT NOT NULL DEFAULT '', note TEXT NOT NULL DEFAULT '',
      request_signature TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 1, total INTEGER NOT NULL CHECK(total >= 0),
      posted_by TEXT NOT NULL DEFAULT '', posted_at TEXT, cancelled_at TEXT,
      cancellation_reason TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      FOREIGN KEY(supplier_id) REFERENCES stock_suppliers(id) ON DELETE RESTRICT)""",
    """CREATE TABLE stock_document_lines (
      id TEXT PRIMARY KEY, document_id TEXT NOT NULL, product_id TEXT NOT NULL,
      product_name TEXT NOT NULL, unit_name TEXT NOT NULL, quantity INTEGER NOT NULL CHECK(quantity >= 0),
      unit_cost INTEGER NOT NULL CHECK(unit_cost >= 0), amount INTEGER NOT NULL CHECK(amount >= 0 AND amount = quantity * unit_cost),
      FOREIGN KEY(document_id) REFERENCES stock_documents(id) ON DELETE RESTRICT,
      FOREIGN KEY(product_id) REFERENCES retail_products(id) ON DELETE RESTRICT,
      UNIQUE(document_id, product_id))""",
    "ALTER TABLE inventory_movements ADD COLUMN document_id TEXT REFERENCES stock_documents(id)",
    "ALTER TABLE inventory_movements ADD COLUMN document_line_id TEXT REFERENCES stock_document_lines(id)",
    "ALTER TABLE inventory_movements ADD COLUMN source TEXT NOT NULL DEFAULT 'legacy'",
    "CREATE INDEX idx_stock_documents_date ON stock_documents(document_date DESC)",
    "CREATE INDEX idx_stock_movements_document ON inventory_movements(document_id)",
    """CREATE TRIGGER stock_document_frozen BEFORE UPDATE ON stock_documents
      WHEN OLD.status != 'draft' AND NOT (
        OLD.status = 'posted' AND NEW.status = 'cancelled' AND length(trim(NEW.cancellation_reason)) > 0
        AND NEW.sequence = OLD.sequence AND NEW.cancelled_at IS NOT NULL AND NEW.id = OLD.id AND NEW.number = OLD.number AND NEW.kind = OLD.kind
        AND NEW.document_date = OLD.document_date AND NEW.supplier_id IS OLD.supplier_id
        AND NEW.supplier_name = OLD.supplier_name AND NEW.prepared_by = OLD.prepared_by
        AND NEW.external_reference = OLD.external_reference AND NEW.note = OLD.note AND NEW.total = OLD.total
        AND NEW.posted_by = OLD.posted_by AND NEW.posted_at = OLD.posted_at
        AND NEW.request_signature = OLD.request_signature AND NEW.revision = OLD.revision + 1 AND NEW.created_at = OLD.created_at)
      BEGIN SELECT RAISE(ABORT, 'posted stock document is immutable'); END""",
    """CREATE TRIGGER stock_document_no_delete BEFORE DELETE ON stock_documents
      BEGIN SELECT RAISE(ABORT, 'stock documents cannot be deleted'); END""",
    """CREATE TRIGGER stock_line_no_update BEFORE UPDATE ON stock_document_lines
      WHEN (SELECT status FROM stock_documents WHERE id = OLD.document_id) != 'draft'
        OR (SELECT status FROM stock_documents WHERE id = NEW.document_id) != 'draft'
      BEGIN SELECT RAISE(ABORT, 'posted stock lines are immutable'); END""",
    """CREATE TRIGGER stock_line_no_delete BEFORE DELETE ON stock_document_lines
      WHEN (SELECT status FROM stock_documents WHERE id = OLD.document_id) != 'draft'
      BEGIN SELECT RAISE(ABORT, 'posted stock lines are immutable'); END""",
    """CREATE TRIGGER stock_line_no_insert BEFORE INSERT ON stock_document_lines
      WHEN (SELECT status FROM stock_documents WHERE id = NEW.document_id) != 'draft'
      BEGIN SELECT RAISE(ABORT, 'posted stock lines are immutable'); END""",
    """CREATE TRIGGER stock_movement_no_update BEFORE UPDATE ON inventory_movements
      BEGIN SELECT RAISE(ABORT, 'stock history is immutable'); END""",
    """CREATE TRIGGER stock_movement_no_delete BEFORE DELETE ON inventory_movements
      BEGIN SELECT RAISE(ABORT, 'stock history is immutable'); END""",
  ];
}
