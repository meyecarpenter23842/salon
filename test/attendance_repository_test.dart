
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:salonmanager/core/database/attendance_schema.dart';
import 'package:salonmanager/core/database/database_schema.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/attendance.dart';
import 'package:salonmanager/core/repositories/sqlite_attendance_repository.dart';
import 'package:salonmanager/core/services/backup_service.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late SensitiveActionService security;
  late SqliteAttendanceRepository repo;
  var now=DateTime(2026,10,7,21);
  setUp(()async{
    await SalonDatabase.instance.close();
    db=await SalonDatabase.instance.initialize();
    now=DateTime(2026,10,7,21);
    security=SensitiveActionService(SalonDatabase.instance);
    repo=SqliteAttendanceRepository(SalonDatabase.instance,security,clock:()=>now);
    await db.insert('employees',{'id':'emp','full_name':'Thợ A','role':'Stylist',
      'status':'Đang làm việc','commission_rate':0.1,
      'created_at':now.toIso8601String(),'updated_at':now.toIso8601String()});
  });
  tearDown(()async{await SalonDatabase.instance.close();});
  Future<void> plan(String request,{DateTime? start,DateTime? end})=>repo.plan(
    requestId:request,employeeId:'emp',label:'Ca đêm',
    start:start??DateTime(2026,10,7,21),end:end??DateTime(2026,10,8,5));
  Future<AttendanceShift> shift()async=>(await repo.fetch(DateTime(2026,10,7))).shifts.first;
  Future<void> stamp(String request,String operation)async=>repo.stamp(
    requestId:request,shift:await shift(),operation:operation);

  test('overnight multiple breaks produce net work and stay visible on next day',()async{
    await plan('plan');await stamp('in','in');
    now=DateTime(2026,10,7,23,30);await stamp('b1','break_start');
    now=DateTime(2026,10,8,0);await stamp('b2','break_end');
    now=DateTime(2026,10,8,2);await stamp('b3','break_start');
    now=DateTime(2026,10,8,2,15);await stamp('b4','break_end');
    expect((await repo.fetch(DateTime(2026,10,8))).shifts,hasLength(1));
    now=DateTime(2026,10,8,5);await stamp('out','out');
    final s=await shift();
    expect(s.state,'completed');expect(s.workDay,'2026-10-07');
    expect(s.workedSeconds,7*3600+15*60);expect(s.revision,7);
    expect(await repo.history(s.id),hasLength(7));
    expect(await db.query('cashier_shifts'),isEmpty);
    expect(await db.query('cash_movements'),isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'),isEmpty);
  });

  test('exact replay returns proof, changed payload and stale edits fail',()async{
    await plan('plan');await plan('plan');
    final initial=await shift();
    await repo.stamp(requestId:'in',shift:initial,operation:'in');
    await repo.stamp(requestId:'in',shift:initial,operation:'in');
    await expectLater(repo.stamp(requestId:'in',shift:initial,operation:'out'),throwsStateError);
    await expectLater(repo.stamp(requestId:'stale',shift:initial,operation:'in'),throwsStateError);
    expect(await repo.history(initial.id),hasLength(2));
  });

  test('two repository writers cannot duplicate clock-in or open two shifts',()async{
    await plan('plan');
    await plan('next',start:DateTime(2026,10,8,7),end:DateTime(2026,10,8,15));
    final initial=await shift();
    final other=SqliteAttendanceRepository(SalonDatabase.instance,security,clock:()=>now);
    final outcomes=await Future.wait([
      repo.stamp(requestId:'a',shift:initial,operation:'in').then((_)=>true,onError:(_)=>false),
      other.stamp(requestId:'b',shift:initial,operation:'in').then((_)=>true,onError:(_)=>false),
    ]);
    expect(outcomes.where((v)=>v),hasLength(1));
    final next=(await repo.fetch(DateTime(2026,10,8))).shifts.singleWhere((s)=>s.state=='planned');
    now=DateTime(2026,10,8,7);
    await expectLater(other.stamp(requestId:'next-in',shift:next,operation:'in'),throwsStateError);
    expect(await db.query('attendance_shifts',where:"state='working'"),hasLength(1));
  });

  test('invalid transitions, open break checkout and overlapping plans roll back',()async{
    await plan('plan');
    await expectLater(plan('overlap'),throwsStateError);
    await expectLater(stamp('earlyout','out'),throwsStateError);
    await stamp('in','in');await stamp('break','break_start');
    await expectLater(stamp('duplicate','break_start'),throwsStateError);
    await expectLater(stamp('out','out'),throwsStateError);
    expect((await shift()).onBreak,isTrue);
    expect(await repo.history((await shift()).id),hasLength(3));
    now=DateTime(2026,10,7,20);
    await expectLater(stamp('backwards','break_end'),throwsArgumentError);
  });

  test('owner corrections require PIN and reason and preserve before/after immutable history',()async{
    await plan('plan');await stamp('in','in');
    now=DateTime(2026,10,8,5);await stamp('out','out');
    final s=await shift();
    Future<void> correct(String reason)=>repo.correct(requestId:'correct',shift:s,state:'completed',
      clockIn:DateTime(2026,10,7,22),clockOut:now,
      breaks:[AttendanceBreak(DateTime(2026,10,8,0),DateTime(2026,10,8,0,30))],
      reason:reason);
    await expectLater(correct(''),throwsArgumentError);
    await security.configureOwnerPin('1234',actorName:'Chủ salon');security.lockOwnerSession();
    await expectLater(correct('Quên giờ vào'),throwsStateError);
    await expectLater(plan('locked',start:DateTime(2026,10,9,9),end:DateTime(2026,10,9,17)),throwsStateError);
    await security.unlockOwner('1234');await correct('Quên giờ vào');await correct('Quên giờ vào');
    expect((await shift()).workedSeconds,6*3600+30*60);
    final event=(await repo.history(s.id)).first;
    expect(event['actor'],'Chủ salon');expect(event['reason'],'Quên giờ vào');
    expect((jsonDecode(event['before_json'] as String) as Map)['clock_in'],s.clockIn!.millisecondsSinceEpoch);
    await expectLater(db.update('attendance_events',{'reason':'changed'}),throwsA(isA<DatabaseException>()));
    await expectLater(db.delete('attendance_events'),throwsA(isA<DatabaseException>()));
    await expectLater(db.delete('attendance_shifts'),throwsA(isA<DatabaseException>()));
    await expectLater(correct('Lý do khác'),throwsStateError);
  });

  test('correction validates break overlap, future and closed/open state',()async{
    await plan('plan');now=DateTime(2026,10,8,5);
    final s=await shift();
    Future<void> correct(List<AttendanceBreak> breaks,{DateTime? end})=>repo.correct(
      requestId:'edit',shift:s,state:'completed',clockIn:DateTime(2026,10,7,21),
      clockOut:end??now,breaks:breaks,reason:'Bổ sung công');
    await expectLater(correct([
      AttendanceBreak(DateTime(2026,10,7,22),DateTime(2026,10,7,23)),
      AttendanceBreak(DateTime(2026,10,7,22,30),DateTime(2026,10,8,0)),
    ]),throwsArgumentError);
    await expectLater(correct([AttendanceBreak(DateTime(2026,10,7,22),null)]),throwsArgumentError);
    await expectLater(correct([],end:DateTime(2026,10,8,6)),throwsArgumentError);
    expect((await shift()).revision,1);
    await correct([]);expect((await shift()).workedSeconds,8*3600);
  });

  test('leave/cancel history retained, inactive staff cannot get new time but old time can close',()async{
    await plan('plan');final s=await shift();
    await repo.correct(requestId:'leave',shift:s,state:'leave',clockIn:null,clockOut:null,
      breaks:[],reason:'Nghỉ theo đề nghị');
    expect((await shift()).workedSeconds,isNull);
    await expectLater(stamp('in','in'),throwsStateError);
    await repo.correct(requestId:'cancel',shift:await shift(),state:'cancelled',
      clockIn:null,clockOut:null,breaks:[],reason:'Đổi lịch');
    await plan('replacement');final replacement=(await repo.fetch(DateTime(2026,10,7))).shifts
      .singleWhere((s)=>s.state=='planned');
    await repo.stamp(requestId:'replacement-in',shift:replacement,operation:'in');
    await db.update('employees',{'status':'Tạm nghỉ'},where:'id=?',whereArgs:['emp']);
    now=DateTime(2026,10,8,5);
    final open=(await repo.fetch(DateTime(2026,10,8))).shifts.single;
    await repo.stamp(requestId:'close-old',shift:open,operation:'out');
    await expectLater(plan('inactive',start:DateTime(2026,10,9,9),end:DateTime(2026,10,9,17)),throwsStateError);
    expect(await repo.history(s.id),hasLength(3));
  });

  test('actual hours cannot overlap another completed shift; cancelled plans cannot reopen over replacement',()async{
    await plan('plan');await stamp('in','in');
    now=DateTime(2026,10,8,5);await stamp('out','out');
    await plan('day',start:DateTime(2026,10,8,7),end:DateTime(2026,10,8,15));
    final planned=(await repo.fetch(DateTime(2026,10,8))).shifts.single;
    now=DateTime(2026,10,8,15);
    await expectLater(repo.correct(requestId:'overlap',shift:planned,state:'completed',
      clockIn:DateTime(2026,10,8,4),clockOut:now,breaks:[],reason:'Bổ sung'),throwsStateError);
    expect((await repo.fetch(DateTime(2026,10,8))).shifts.single.revision,1);
    await repo.correct(requestId:'cancel-day',shift:planned,state:'cancelled',
      clockIn:null,clockOut:null,breaks:[],reason:'Đổi lịch');
    await plan('replace-day',start:DateTime(2026,10,8,7),end:DateTime(2026,10,8,15));
    final cancelled=(await repo.fetch(DateTime(2026,10,8))).shifts.singleWhere((s)=>s.state=='cancelled');
    await expectLater(repo.correct(requestId:'restore',shift:cancelled,state:'planned',
      clockIn:null,clockOut:null,breaks:[],reason:'Khôi phục'),throwsStateError);
  });

  test('atomic event failure rolls back the clock and revision',()async{
    await plan('plan');final s=await shift();
    await db.execute("""CREATE TRIGGER attendance_fixture_failure BEFORE INSERT ON attendance_events
      WHEN NEW.operation='in' BEGIN SELECT RAISE(ABORT,'fixture'); END""");
    await expectLater(repo.stamp(requestId:'in',shift:s,operation:'in'),throwsA(isA<DatabaseException>()));
    expect((await shift()).state,'planned');expect((await shift()).revision,1);
    expect(await repo.history(s.id),hasLength(1));
  });

  test('current-version backup missing attendance history is rejected',()async{
    await plan('plan');
    await db.execute('DROP TABLE attendance_events');
    final validation=await const BackupService().validateBackupFile(db.path);
    expect(validation.isValid,isFalse);
    expect(validation.message,contains('attendance_events'));
  });

  test('schema 21 partial migration preserves attendance and backup restore keeps history',()async{
    await plan('plan');await stamp('in','in');
    final old=await shift();
    await AttendanceSchema.install(db); // interrupted upgrade can already contain DDL
    await db.execute('PRAGMA user_version = 21');
    await db.update('app_settings',{'value':'21'},where:'key=?',whereArgs:['schema_version']);
    await SalonDatabase.instance.close();
    db=await SalonDatabase.instance.initialize(preserveExistingTestDatabase:true);
    expect(await db.getVersion(),DatabaseSchema.version);
    expect((await shift()).data,old.data);
    final backup=await const BackupService().createBackup();expect(backup.success,isTrue);
    now=DateTime(2026,10,8,5);await stamp('out','out');
    final restored=await const BackupService().restoreFromBackup(backup.filePath!);
    expect(restored.success,isTrue);
    expect((await shift()).state,'working');
    expect(await repo.history(old.id),hasLength(2));
    db=await SalonDatabase.instance.database;
    expect(await db.rawQuery('PRAGMA foreign_key_check'),isEmpty);
  });
}
