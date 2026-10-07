import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/database/employee_title_schema.dart';
import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/models/catalog_option.dart';
import 'package:salonmanager/core/models/employee_upsert_input.dart';
import 'package:salonmanager/core/repositories/catalog_options_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_employees_repository.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';
import 'package:salonmanager/core/services/backup_service.dart';

EmployeeUpsertInput input(
  String role, {
  String? titleId,
  String name = 'Thợ A',
  String? expected,
}) => EmployeeUpsertInput(
  fullName: name,
  role: role,
  titleOptionId: titleId,
  expectedUpdatedAt:expected,
  status: 'Đang làm việc',
  phone: '0900000000',
  shift: 'Ca sáng',
  specialty: 'Tóc',
  commissionLabel: '10%',
  todaySchedule: '',
  servicesDone: 0,
  monthlyRevenue: '',
  rating: '',
  note: 'Ghi chú',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late SensitiveActionService security;
  late SqliteCatalogOptionsRepository titles;
  late SqliteEmployeesRepository employees;
  setUp(() async {
    await SalonDatabase.instance.close();
    db = await SalonDatabase.instance.initialize();
    security = SensitiveActionService(SalonDatabase.instance);
    titles = SqliteCatalogOptionsRepository(
      SalonDatabase.instance,
      security: security,
    );
    employees = SqliteEmployeesRepository(
      SalonDatabase.instance,
      FakeSalonDataSource(),
      security: security,
    );
  });
  tearDown(() async {
    await SalonDatabase.instance.close();
  });
  Future<CatalogOption> title(String name) async {
    await titles.createOption(CatalogOptionKind.employeeTitle, name);
    return (await titles.fetchOptions(
      CatalogOptionKind.employeeTitle,
    )).singleWhere((o) => catalogNameKey(o.name) == catalogNameKey(name));
  }

  test(
    'custom title stable ID, normalized uniqueness, usage and rename refresh current profile',
    () async {
      final t = await title('  Trưởng   nhóm  ');
      expect(t.name, 'Trưởng nhóm');
      final e = await employees.saveEmployee(input(t.name, titleId: t.id));
      expect(e['titleOptionId'], t.id);
      await titles.createOption(CatalogOptionKind.employeeTitle, 'trưởng nhóm');
      expect(
        (await titles.fetchOptions(
          CatalogOptionKind.employeeTitle,
        )).where((o) => catalogNameKey(o.name) == 'trưởng nhóm'),
        hasLength(1),
      );
      expect(
        (await titles.fetchOptions(
          CatalogOptionKind.employeeTitle,
        )).singleWhere((o) => o.id == t.id).usageCount,
        1,
      );
      final snapshots = await db.query('payroll_runs');
      await titles.renameOption(t.id, 'Quản lý kỹ thuật');
      expect(
        (await employees.fetchEmployeesView()).single['role'],
        'Quản lý kỹ thuật',
      );
      expect((await employees.fetchEmployeesView()).single['id'], e['id']);
      expect(await db.query('payroll_runs'), snapshots);
      final audit = await db.query(
        'audit_events',
        where: 'action=?',
        whereArgs: ['employee_title_rename'],
      );
      expect(
        (jsonDecode(audit.single['detail'] as String) as Map)['before']['name'],
        'Trưởng nhóm',
      );
      await expectLater(titles.renameOption(t.id, 'Lễ tân'), throwsStateError);
    },
  );
  test(
    'inactive title retained for old profile but rejected for new assignment; reactivation restores picker',
    () async {
      final t = await title('Thợ lâu năm');
      final e = await employees.saveEmployee(input(t.name, titleId: t.id));
      await titles.setOptionActive(t.id, false);
      expect(
        await titles.fetchOptionNames(CatalogOptionKind.employeeTitle),
        isNot(contains(t.name)),
      );
      await employees.saveEmployee(
        input(t.name, titleId: t.id, name: 'Đổi thông tin'),
        existingId: e['id'] as String,
      );
      await expectLater(
        employees.saveEmployee(input(t.name, titleId: t.id, name: 'Mới')),
        throwsStateError,
      );
      await expectLater(
        titles.createOption(CatalogOptionKind.employeeTitle, t.name),
        throwsStateError,
      );
      await titles.setOptionActive(t.id, true);
      expect(
        await titles.fetchOptionNames(CatalogOptionKind.employeeTitle),
        contains(t.name),
      );
    },
  );
  test(
    'stale renamed title or wrong catalog kind cannot create or overwrite employee',
    () async {
      final t = await title('Cũ');
      await titles.renameOption(t.id, 'Mới');
      await expectLater(
        employees.saveEmployee(input('Cũ', titleId: t.id)),
        throwsStateError,
      );
      final unit = (await titles.fetchOptions(
        CatalogOptionKind.productUnit,
      )).first;
      await expectLater(
        employees.saveEmployee(input(unit.name, titleId: unit.id)),
        throwsStateError,
      );
      expect(await db.query('employees'), isEmpty);
      await expectLater(employees.saveEmployee(input('')), throwsArgumentError);
    },
  );
  test(
    'Owner gate on title create rename deactivate and assignment; title name grants no session',
    () async {
      final t = await title('Owner');
      final e = await employees.saveEmployee(input('Owner', titleId: t.id));
      await security.configureOwnerPin('1234');
      security.lockOwnerSession();
      await expectLater(title('Chủ salon'), throwsStateError);
      await expectLater(titles.renameOption(t.id, 'Chủ'), throwsStateError);
      await expectLater(titles.setOptionActive(t.id, false), throwsStateError);
      await expectLater(
        employees.saveEmployee(input('Lễ tân'), existingId: e['id'] as String),
        throwsStateError,
      );
      expect(security.isOwnerSessionActive, isFalse);
      expect((await employees.fetchEmployeesView()).single['role'], 'Owner');
      expect(await db.query('commission_entries'), isEmpty);
      expect(await db.query('payroll_policies'), isEmpty);
      await security.unlockOwner('1234');
      await titles.renameOption(t.id, 'Chủ kỹ thuật');
    },
  );
  test(
    'audit failure rolls back rename and assignment with employee state intact',
    () async {
      final t = await title('Thợ A');
      final e = await employees.saveEmployee(input(t.name, titleId: t.id));
      await db.execute(
        """CREATE TRIGGER fail_title BEFORE INSERT ON audit_events
      WHEN NEW.action LIKE 'employee_title_%' BEGIN SELECT RAISE(ABORT,'fixture'); END""",
      );
      await expectLater(
        titles.renameOption(t.id, 'Thợ B'),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await titles.fetchOptions(
          CatalogOptionKind.employeeTitle,
        )).singleWhere((o) => o.id == t.id).name,
        'Thợ A',
      );
      await expectLater(
        employees.saveEmployee(input('Lễ tân'), existingId: e['id'] as String),
        throwsA(isA<DatabaseException>()),
      );
      expect((await employees.fetchEmployeesView()).single['role'], 'Thợ A');
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'legacy whitespace/custom/empty titles migrate without changing employee text or timestamps',
    () async {
      final stamp = DateTime(2026, 1, 1).toIso8601String();
      for (final pair in [
        ('a', '  Chuyên   viên cũ '),
        ('b', 'chuyên viên cũ'),
        ('c', ''),
      ]) {
        await db.insert('employees', {
          'id': pair.$1,
          'full_name': pair.$1,
          'role': pair.$2,
          'created_at': stamp,
          'updated_at': stamp,
        });
      }
      final before = await db.query('employees');
      await EmployeeTitleSchema.install(db);
      await EmployeeTitleSchema.install(db);
      await db.execute('PRAGMA user_version=23');
      await db.update(
        'app_settings',
        {'value': '23'},
        where: 'key=?',
        whereArgs: ['schema_version'],
      );
      await SalonDatabase.instance.close();
      db = await SalonDatabase.instance.initialize(
        preserveExistingTestDatabase: true,
      );
      expect(await db.getVersion(), 24);
      final after = await db.query('employees');
      for (var i = 0; i < before.length; i++) {
        expect(after[i]['role'], before[i]['role']);
        expect(after[i]['updated_at'], stamp);
        expect(after[i]['id'], before[i]['id']);
      }
      expect(after[0]['title_option_id'], after[1]['title_option_id']);
      expect(after[2]['title_option_id'], isNull);
      await SalonDatabase.instance.close();
      db = await SalonDatabase.instance.initialize(
        preserveExistingTestDatabase: true,
      );
      expect(await db.query('employees'), after);
    },
  );
  test(
    'concurrent creates share one stable catalog ID and one creation audit',
    () async {
      await Future.wait(
        [
          'Thợ spa',
          ' thợ  spa ',
        ].map((n) => titles.createOption(CatalogOptionKind.employeeTitle, n)),
      );
      expect(
        (await titles.fetchOptions(
          CatalogOptionKind.employeeTitle,
        )).where((o) => catalogNameKey(o.name) == 'thợ spa'),
        hasLength(1),
      );
      final audit = await db.query(
        'audit_events',
        where: 'action=?',
        whereArgs: ['employee_title_create'],
      );
      expect(audit, hasLength(1));
    },
  );
  test(
    'backup restore recovers title names active flags and employee link; schema24 missing link rejected',
    () async {
      final t = await title('Thợ A');
      await employees.saveEmployee(input(t.name, titleId: t.id));
      final backup = await const BackupService().createBackup();
      expect(backup.success, isTrue);
      await titles.renameOption(t.id, 'Thợ B');
      await titles.setOptionActive(t.id, false);
      expect(
        (await const BackupService().restoreFromBackup(
          backup.filePath!,
        )).success,
        isTrue,
      );
      db = await SalonDatabase.instance.database;
      expect((await employees.fetchEmployeesView()).single['role'], 'Thợ A');
      expect(
        (await titles.fetchOptions(
          CatalogOptionKind.employeeTitle,
        )).singleWhere((o) => o.id == t.id).isActive,
        isTrue,
      );
      await db.execute('DROP INDEX idx_employee_title');
      await db.execute('ALTER TABLE employees DROP COLUMN title_option_id');
      final invalid = await const BackupService().validateBackupFile(db.path);
      expect(invalid.isValid, isFalse);
    },
  );
}

