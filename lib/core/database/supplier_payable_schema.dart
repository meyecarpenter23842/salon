import 'package:sqflite/sqflite.dart';

/// Schema 26: supplier accounts payable, immutable payments and allocations.
///
/// Installation never backfills old stock receipts or infers paid/debt state
/// from legacy stock documents, cash movements, notes, or transfer text.
class SupplierPayableSchema {
  static Future<void> install(DatabaseExecutor db) async {
    for (final sql in statements) {
      await db.execute(sql);
    }
  }

  static const statements = [
    """CREATE TABLE IF NOT EXISTS supplier_payable_obligations (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL CHECK(kind IN ('charge','reversal')),
      original_id TEXT UNIQUE,
      supplier_id TEXT NOT NULL,
      supplier_name TEXT NOT NULL,
      source_type TEXT NOT NULL CHECK(source_type IN ('stock_receipt','opening')),
      source_id TEXT,
      source_number TEXT NOT NULL,
      source_date TEXT NOT NULL,
      amount INTEGER NOT NULL,
      reason TEXT NOT NULL CHECK(length(trim(reason)) > 0),
      external_reference TEXT NOT NULL,
      actor TEXT NOT NULL,
      signature TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK((kind='charge' AND original_id IS NULL AND amount > 0)
        OR (kind='reversal' AND original_id IS NOT NULL AND amount < 0)),
      CHECK((source_type='stock_receipt' AND source_id IS NOT NULL)
        OR (source_type='opening' AND source_id IS NULL)),
      FOREIGN KEY(original_id) REFERENCES supplier_payable_obligations(id) ON DELETE RESTRICT,
      FOREIGN KEY(supplier_id) REFERENCES stock_suppliers(id) ON DELETE RESTRICT,
      FOREIGN KEY(source_id) REFERENCES stock_documents(id) ON DELETE RESTRICT)""",
    """CREATE TABLE IF NOT EXISTS supplier_payments (
      id TEXT PRIMARY KEY,
      supplier_id TEXT NOT NULL,
      supplier_name TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('payment','reversal')),
      original_payment_id TEXT UNIQUE,
      amount INTEGER NOT NULL,
      method TEXT NOT NULL CHECK(method IN ('cash','transfer')),
      reference TEXT NOT NULL,
      note TEXT NOT NULL,
      actor TEXT NOT NULL,
      cash_movement_id TEXT UNIQUE,
      signature TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK((kind='payment' AND original_payment_id IS NULL AND amount > 0)
        OR (kind='reversal' AND original_payment_id IS NOT NULL AND amount < 0)),
      CHECK(method!='cash' OR cash_movement_id IS NOT NULL),
      CHECK(method!='transfer' OR length(trim(reference)) > 0),
      FOREIGN KEY(supplier_id) REFERENCES stock_suppliers(id) ON DELETE RESTRICT,
      FOREIGN KEY(original_payment_id) REFERENCES supplier_payments(id) ON DELETE RESTRICT,
      FOREIGN KEY(cash_movement_id) REFERENCES cash_movements(id) ON DELETE RESTRICT)""",
    """CREATE TABLE IF NOT EXISTS supplier_payment_allocations (
      id TEXT PRIMARY KEY,
      payment_id TEXT NOT NULL,
      obligation_id TEXT NOT NULL,
      amount INTEGER NOT NULL CHECK(amount != 0),
      created_at TEXT NOT NULL,
      UNIQUE(payment_id, obligation_id),
      FOREIGN KEY(payment_id) REFERENCES supplier_payments(id) ON DELETE RESTRICT,
      FOREIGN KEY(obligation_id) REFERENCES supplier_payable_obligations(id) ON DELETE RESTRICT)""",
    """CREATE TABLE IF NOT EXISTS supplier_payable_events (
      request_id TEXT PRIMARY KEY,
      operation TEXT NOT NULL,
      target_type TEXT NOT NULL,
      target_id TEXT NOT NULL,
      signature TEXT NOT NULL,
      actor TEXT NOT NULL,
      detail TEXT NOT NULL,
      before_json TEXT,
      after_json TEXT NOT NULL,
      created_at TEXT NOT NULL)""",
    """CREATE UNIQUE INDEX IF NOT EXISTS idx_supplier_payable_stock_source
      ON supplier_payable_obligations(source_id)
      WHERE kind='charge' AND source_type='stock_receipt'""",
    """CREATE INDEX IF NOT EXISTS idx_supplier_payable_supplier_date
      ON supplier_payable_obligations(supplier_id,source_date DESC,created_at DESC)""",
    """CREATE INDEX IF NOT EXISTS idx_supplier_alloc_obligation
      ON supplier_payment_allocations(obligation_id,payment_id)""",
    """CREATE INDEX IF NOT EXISTS idx_supplier_payment_supplier
      ON supplier_payments(supplier_id,created_at DESC)""",
    """CREATE UNIQUE INDEX IF NOT EXISTS idx_supplier_transfer_reference
      ON supplier_payments(reference COLLATE NOCASE)
      WHERE method='transfer'""",
    """CREATE TRIGGER IF NOT EXISTS supplier_obligation_no_update
      BEFORE UPDATE ON supplier_payable_obligations
      BEGIN SELECT RAISE(ABORT,'supplier payable history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS supplier_obligation_no_delete
      BEFORE DELETE ON supplier_payable_obligations
      BEGIN SELECT RAISE(ABORT,'supplier payable history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS supplier_payment_no_update
      BEFORE UPDATE ON supplier_payments
      BEGIN SELECT RAISE(ABORT,'supplier payment proof is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS supplier_payment_no_delete
      BEFORE DELETE ON supplier_payments
      BEGIN SELECT RAISE(ABORT,'supplier payment proof is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS supplier_allocation_no_update
      BEFORE UPDATE ON supplier_payment_allocations
      BEGIN SELECT RAISE(ABORT,'supplier allocation history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS supplier_allocation_no_delete
      BEFORE DELETE ON supplier_payment_allocations
      BEGIN SELECT RAISE(ABORT,'supplier allocation history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS supplier_event_no_update
      BEFORE UPDATE ON supplier_payable_events
      BEGIN SELECT RAISE(ABORT,'supplier payable event history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS supplier_event_no_delete
      BEFORE DELETE ON supplier_payable_events
      BEGIN SELECT RAISE(ABORT,'supplier payable event history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS supplier_cash_no_update
      BEFORE UPDATE ON cash_movements
      WHEN EXISTS(SELECT 1 FROM supplier_payments WHERE cash_movement_id=OLD.id)
      BEGIN SELECT RAISE(ABORT,'supplier cash proof is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS supplier_cash_no_delete
      BEFORE DELETE ON cash_movements
      WHEN EXISTS(SELECT 1 FROM supplier_payments WHERE cash_movement_id=OLD.id)
      BEGIN SELECT RAISE(ABORT,'supplier cash proof is immutable'); END""",
  ];
}
