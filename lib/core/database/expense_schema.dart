import 'package:sqflite/sqflite.dart';

/// Schema 25: operating expenses and immutable payment/reversal proof.
///
/// Installation is idempotent and never infers expenses or payments from
/// legacy cash movements, stock receipts, payroll, or commission history.
class ExpenseSchema {
  static Future<void> install(DatabaseExecutor db) async {
    for (final sql in statements) {
      await db.execute(sql);
    }
  }

  static const statements = [
    """CREATE TABLE IF NOT EXISTS expense_categories (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      normalized_name TEXT NOT NULL UNIQUE,
      is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
      revision INTEGER NOT NULL DEFAULT 1 CHECK(revision >= 1),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL)""",
    """CREATE TABLE IF NOT EXISTS expense_entries (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL CHECK(kind IN ('expense','reversal')),
      original_id TEXT UNIQUE,
      category_id TEXT NOT NULL,
      category_name TEXT NOT NULL,
      expense_date TEXT NOT NULL,
      payee TEXT NOT NULL,
      amount INTEGER NOT NULL,
      reason TEXT NOT NULL CHECK(length(trim(reason)) > 0),
      external_reference TEXT NOT NULL,
      actor TEXT NOT NULL,
      signature TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK((kind='expense' AND original_id IS NULL AND amount > 0)
        OR (kind='reversal' AND original_id IS NOT NULL AND amount < 0)),
      FOREIGN KEY(category_id) REFERENCES expense_categories(id) ON DELETE RESTRICT,
      FOREIGN KEY(original_id) REFERENCES expense_entries(id) ON DELETE RESTRICT)""",
    """CREATE TABLE IF NOT EXISTS expense_payments (
      id TEXT PRIMARY KEY,
      expense_id TEXT NOT NULL,
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
      FOREIGN KEY(expense_id) REFERENCES expense_entries(id) ON DELETE RESTRICT,
      FOREIGN KEY(original_payment_id) REFERENCES expense_payments(id) ON DELETE RESTRICT,
      FOREIGN KEY(cash_movement_id) REFERENCES cash_movements(id) ON DELETE RESTRICT)""",
    """CREATE TABLE IF NOT EXISTS expense_events (
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
    "CREATE INDEX IF NOT EXISTS idx_expense_entries_date ON expense_entries(expense_date DESC,created_at DESC)",
    "CREATE INDEX IF NOT EXISTS idx_expense_entries_category ON expense_entries(category_id,expense_date DESC)",
    "CREATE INDEX IF NOT EXISTS idx_expense_payments_expense ON expense_payments(expense_id,created_at DESC)",
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_expense_transfer_reference ON expense_payments(reference COLLATE NOCASE) WHERE method='transfer'",
    """CREATE TRIGGER IF NOT EXISTS expense_category_revision_guard BEFORE UPDATE ON expense_categories
      WHEN NEW.id!=OLD.id OR NEW.created_at!=OLD.created_at OR NEW.revision!=OLD.revision+1
      BEGIN SELECT RAISE(ABORT,'expense category revision conflict'); END""",
    """CREATE TRIGGER IF NOT EXISTS expense_category_no_delete BEFORE DELETE ON expense_categories
      BEGIN SELECT RAISE(ABORT,'expense categories cannot be deleted'); END""",
    """CREATE TRIGGER IF NOT EXISTS expense_entry_no_update BEFORE UPDATE ON expense_entries
      BEGIN SELECT RAISE(ABORT,'expense history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS expense_entry_no_delete BEFORE DELETE ON expense_entries
      BEGIN SELECT RAISE(ABORT,'expense history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS expense_payment_no_update BEFORE UPDATE ON expense_payments
      BEGIN SELECT RAISE(ABORT,'expense payment proof is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS expense_payment_no_delete BEFORE DELETE ON expense_payments
      BEGIN SELECT RAISE(ABORT,'expense payment proof is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS expense_event_no_update BEFORE UPDATE ON expense_events
      BEGIN SELECT RAISE(ABORT,'expense event history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS expense_event_no_delete BEFORE DELETE ON expense_events
      BEGIN SELECT RAISE(ABORT,'expense event history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS expense_cash_no_update BEFORE UPDATE ON cash_movements
      WHEN EXISTS(SELECT 1 FROM expense_payments WHERE cash_movement_id=OLD.id)
      BEGIN SELECT RAISE(ABORT,'expense cash proof is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS expense_cash_no_delete BEFORE DELETE ON cash_movements
      WHEN EXISTS(SELECT 1 FROM expense_payments WHERE cash_movement_id=OLD.id)
      BEGIN SELECT RAISE(ABORT,'expense cash proof is immutable'); END""",
  ];
}
