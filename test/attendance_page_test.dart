
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/attendance.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
import 'package:salonmanager/core/repositories/sqlite_attendance_repository.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';
import 'package:salonmanager/features/employees/presentation/pages/attendance_page.dart';

class _ViewRepository extends SqliteAttendanceRepository {
  _ViewRepository():super(SalonDatabase.instance,SensitiveActionService(SalonDatabase.instance));
  final row=<String,Object?>{
    'id':'a','employee_id':'e','employee_name':'Thợ A','label':'Ca sáng',
    'work_day':SqliteAttendanceRepository.dayKey(DateTime.now()),
    'planned_start':DateTime.now().millisecondsSinceEpoch,
    'planned_end':DateTime.now().add(const Duration(hours:8)).millisecondsSinceEpoch,
    'state':'working','clock_in':DateTime.now().millisecondsSinceEpoch,
    'clock_out':null,'breaks_json':'[]','revision':1,
  };
  @override Future<AttendanceSnapshot> fetch(DateTime day)async=>AttendanceSnapshot(
    [{'id':'e','full_name':'Thợ A','status':'Đang làm việc'}],[AttendanceShift(row)]);
  @override Future<List<Map<String,Object?>>> history(String id)async=>[
    {'operation':'in','revision':1,'actor':'Máy salon','reason':'Chấm tại desktop',
      'created_at':DateTime.now().toIso8601String(),'before_json':null,'after_json':'{"id":"a","employee_id":"e","employee_name":"Thợ A","label":"Ca sáng","work_day":"2026-10-07","planned_start":0,"planned_end":1,"state":"working","clock_in":0,"clock_out":null,"breaks_json":"[]","revision":1}'},
  ];
}
void main(){
  for(final size in [const Size(800,600),const Size(1366,768)]){
    testWidgets('attendance desktop controls and history fit ${size.width}',(tester)async{
      tester.view.physicalSize=size;tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(overrides:[
        attendanceRepositoryProvider.overrideWithValue(_ViewRepository())],
        child:const MaterialApp(home:AttendancePage())));
      await tester.pumpAndSettle();
      expect(find.text('Chấm công'),findsOneWidget);
      expect(find.text('Bắt đầu nghỉ'),findsOneWidget);
      expect(find.text('Ra ca'),findsOneWidget);
      expect(tester.takeException(),isNull);
      await tester.tap(find.text('Lịch sử'));await tester.pumpAndSettle();
      expect(find.text('Lịch sử công · Thợ A'),findsOneWidget);
      expect(find.text('Lý do: Chấm tại desktop'),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  }
}
