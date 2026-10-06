import 'package:sqflite/sqflite.dart';

/// Schema 21. Installation never backfills estimates as money owed.
class CommissionSchema {
  static Future<void> install(DatabaseExecutor db) async {
    for (final sql in statements) { await db.execute(sql); }
  }
  static const statements = [
    """CREATE TABLE commission_periods (
      period TEXT PRIMARY KEY, closed_at TEXT NOT NULL, closed_by TEXT NOT NULL)""",
    """CREATE TABLE commission_entries (
      id TEXT PRIMARY KEY, invoice_id TEXT NOT NULL, line_id TEXT NOT NULL,
      employee_id TEXT NOT NULL, employee_name TEXT NOT NULL, title TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('earned','reversal')),
      original_id TEXT UNIQUE, period TEXT NOT NULL,
      rate_bps INTEGER NOT NULL CHECK(rate_bps BETWEEN 0 AND 10000),
      basis INTEGER NOT NULL CHECK(basis >= 0), amount INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      CHECK((kind='earned' AND original_id IS NULL AND amount >= 0)
        OR (kind='reversal' AND original_id IS NOT NULL AND amount <= 0)),
      UNIQUE(line_id,kind),
      FOREIGN KEY(invoice_id) REFERENCES invoices(id) ON DELETE RESTRICT,
      FOREIGN KEY(line_id) REFERENCES invoice_items(id) ON DELETE RESTRICT,
      FOREIGN KEY(employee_id) REFERENCES employees(id) ON DELETE RESTRICT,
      FOREIGN KEY(original_id) REFERENCES commission_entries(id) ON DELETE RESTRICT)""",
    """CREATE TABLE commission_payouts (
      id TEXT PRIMARY KEY, employee_id TEXT NOT NULL, employee_name TEXT NOT NULL,
      amount INTEGER NOT NULL CHECK(amount > 0),
      method TEXT NOT NULL CHECK(method IN ('cash','transfer')),
      reference TEXT NOT NULL, note TEXT NOT NULL, actor TEXT NOT NULL,
      cash_movement_id TEXT UNIQUE, signature TEXT NOT NULL, created_at TEXT NOT NULL,
      CHECK(method != 'cash' OR cash_movement_id IS NOT NULL),
      CHECK(method != 'transfer' OR length(trim(reference)) > 0),
      FOREIGN KEY(employee_id) REFERENCES employees(id) ON DELETE RESTRICT,
      FOREIGN KEY(cash_movement_id) REFERENCES cash_movements(id) ON DELETE RESTRICT)""",
    "CREATE INDEX idx_commission_employee_period ON commission_entries(employee_id,period)",
    "CREATE INDEX idx_commission_payout_employee ON commission_payouts(employee_id)",
    """CREATE TRIGGER commission_closed_no_entry BEFORE INSERT ON commission_entries
      WHEN EXISTS(SELECT 1 FROM commission_periods WHERE period=NEW.period)
      BEGIN SELECT RAISE(ABORT,'commission period is closed'); END""",
    """CREATE TRIGGER commission_entry_no_update BEFORE UPDATE ON commission_entries
      BEGIN SELECT RAISE(ABORT,'commission history is immutable'); END""",
    """CREATE TRIGGER commission_entry_no_delete BEFORE DELETE ON commission_entries
      BEGIN SELECT RAISE(ABORT,'commission history is immutable'); END""",
    """CREATE TRIGGER commission_period_no_update BEFORE UPDATE ON commission_periods
      BEGIN SELECT RAISE(ABORT,'commission period is immutable'); END""",
    """CREATE TRIGGER commission_period_no_delete BEFORE DELETE ON commission_periods
      BEGIN SELECT RAISE(ABORT,'commission period is immutable'); END""",
    """CREATE TRIGGER commission_payout_no_update BEFORE UPDATE ON commission_payouts
      BEGIN SELECT RAISE(ABORT,'commission payout is immutable'); END""",
    """CREATE TRIGGER commission_payout_no_delete BEFORE DELETE ON commission_payouts
      BEGIN SELECT RAISE(ABORT,'commission payout is immutable'); END""",
    """CREATE TRIGGER commission_cash_no_update BEFORE UPDATE ON cash_movements
      WHEN EXISTS(SELECT 1 FROM commission_payouts WHERE cash_movement_id=OLD.id)
      BEGIN SELECT RAISE(ABORT,'commission cash proof is immutable'); END""",
    """CREATE TRIGGER commission_cash_no_delete BEFORE DELETE ON cash_movements
      WHEN EXISTS(SELECT 1 FROM commission_payouts WHERE cash_movement_id=OLD.id)
      BEGIN SELECT RAISE(ABORT,'commission cash proof is immutable'); END""",
  ];
}
