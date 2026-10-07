
import 'package:sqflite/sqflite.dart';

/// Schema 22: attendance is independent of cashier shifts and appointments.
class AttendanceSchema {
  static Future<void> install(DatabaseExecutor db) async {
    for (final statement in statements) {
      await db.execute(statement);
    }
  }

  static const statements = [
    """CREATE TABLE IF NOT EXISTS attendance_shifts (
      id TEXT PRIMARY KEY, employee_id TEXT NOT NULL, employee_name TEXT NOT NULL,
      label TEXT NOT NULL CHECK(length(trim(label)) > 0),
      work_day TEXT NOT NULL, planned_start INTEGER NOT NULL,
      planned_end INTEGER NOT NULL CHECK(planned_end > planned_start),
      state TEXT NOT NULL CHECK(state IN ('planned','working','completed','leave','cancelled')),
      clock_in INTEGER, clock_out INTEGER, breaks_json TEXT NOT NULL DEFAULT '[]',
      revision INTEGER NOT NULL CHECK(revision >= 1),
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      CHECK((state IN ('planned','leave','cancelled') AND clock_in IS NULL AND clock_out IS NULL)
        OR (state='working' AND clock_in IS NOT NULL AND clock_out IS NULL)
        OR (state='completed' AND clock_in IS NOT NULL AND clock_out IS NOT NULL AND clock_out >= clock_in)),
      FOREIGN KEY(employee_id) REFERENCES employees(id) ON DELETE RESTRICT)""",
    "CREATE INDEX IF NOT EXISTS idx_attendance_day ON attendance_shifts(work_day,employee_id)",
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_one_open ON attendance_shifts(employee_id) WHERE state='working'",
    """CREATE TABLE IF NOT EXISTS attendance_events (
      id TEXT PRIMARY KEY, shift_id TEXT NOT NULL, revision INTEGER NOT NULL,
      operation TEXT NOT NULL, actor TEXT NOT NULL, reason TEXT NOT NULL,
      signature TEXT NOT NULL, before_json TEXT, after_json TEXT NOT NULL,
      created_at TEXT NOT NULL, UNIQUE(shift_id,revision),
      FOREIGN KEY(shift_id) REFERENCES attendance_shifts(id) ON DELETE RESTRICT)""",
    """CREATE TRIGGER IF NOT EXISTS attendance_event_no_update BEFORE UPDATE ON attendance_events
      BEGIN SELECT RAISE(ABORT,'attendance history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS attendance_event_no_delete BEFORE DELETE ON attendance_events
      BEGIN SELECT RAISE(ABORT,'attendance history is immutable'); END""",
    """CREATE TRIGGER IF NOT EXISTS attendance_shift_no_delete BEFORE DELETE ON attendance_shifts
      BEGIN SELECT RAISE(ABORT,'cancel attendance instead of deleting history'); END""",
    """CREATE TRIGGER IF NOT EXISTS attendance_revision_guard BEFORE UPDATE ON attendance_shifts
      WHEN NEW.revision != OLD.revision + 1
      BEGIN SELECT RAISE(ABORT,'attendance revision conflict'); END""",
  ];
}
