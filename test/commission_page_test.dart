import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
import 'package:salonmanager/core/repositories/sqlite_commission_repository.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';
import 'package:salonmanager/features/employees/presentation/pages/commission_page.dart';

class _ViewRepository extends SqliteCommissionRepository {
  _ViewRepository():super(SalonDatabase.instance,SensitiveActionService(SalonDatabase.instance));
  @override Future<CommissionSnapshot> fetch() async=>const CommissionSnapshot(
    periods:['2026-09'],closed:{'2026-09'},
    accounts:[CommissionAccount(id:'e',name:'Thợ A',earned:10000,settled:10000,paid:4000)],
    entries:[],payouts:[]);
}
void main(){
  for(final size in [const Size(1024,768),const Size(1366,768)]){
    testWidgets('commission workspace readable with ${size.width.toInt()} viewport',(tester)async{
      tester.view.physicalSize=size;tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(overrides:[
        commissionRepositoryProvider.overrideWithValue(_ViewRepository())],
        child:const MaterialApp(home:CommissionPage())));
      await tester.pumpAndSettle();
      expect(find.text('Hoa hồng và chi trả'),findsOneWidget);
      expect(find.text('Trả / đối chiếu khoản chờ'),findsOneWidget);
      expect(find.text('Còn phải trả / bù trừ'),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  }
}
