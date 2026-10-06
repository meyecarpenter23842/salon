import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/repositories/commission_ledger.dart';
import 'package:salonmanager/core/repositories/sqlite_commission_repository.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';
import 'package:salonmanager/core/services/backup_service.dart';
import 'package:salonmanager/core/repositories/sqlite_employees_repository.dart';
import 'package:salonmanager/core/data/fake/fake_salon_data_source.dart';
import 'package:salonmanager/core/models/employee_upsert_input.dart';
import 'package:salonmanager/core/repositories/sqlite_billing_sessions_repository.dart';
import 'package:salonmanager/core/repositories/sqlite_invoices_repository.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/core/lan/lan_write_engine.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late SensitiveActionService security;
  late SqliteCommissionRepository repo;
  var now=DateTime(2026,10,1);
  setUp(() async{
    await SalonDatabase.instance.close();
    db=await SalonDatabase.instance.initialize();
    now=DateTime(2026,10,1);
    security=SensitiveActionService(SalonDatabase.instance);
    repo=SqliteCommissionRepository(SalonDatabase.instance,security,clock:()=>now);
    final stamp=DateTime(2026,9,1).toIso8601String();
    await db.insert('customers',{'id':'cust','full_name':'Khách','phone':'0','created_at':stamp,'updated_at':stamp});
    await db.insert('employees',{'id':'emp','full_name':'Thợ A','role':'Stylist','commission_rate':0.1,
      'commission_label':'10%','created_at':stamp,'updated_at':stamp});
  });
  tearDown(() async{await SalonDatabase.instance.close();});

  Future<void> invoice(String id,{int total=100000,int line=100000,DateTime? paid,bool retail=false}) async{
    final date=paid??DateTime(2026,9,15);
    await db.insert('invoices',{'id':id,'customer_id':'cust','subtotal':line,
      'discount_amount':line-total,'total_amount':total,'payment_method':'Tiền mặt',
      'paid_at':date.toIso8601String(),'created_at':date.toIso8601String(),'updated_at':date.toIso8601String()});
    await db.insert('invoice_items',{'id':'line-$id','invoice_id':id,'item_type':'service',
      'employee_id':'emp','title':'Cắt tóc','quantity':1,'unit_price':line,'total_price':line});
    if(retail) { await db.insert('invoice_items',{'id':'retail-$id','invoice_id':id,'item_type':'retail',
      'employee_id':'emp','title':'Sản phẩm','quantity':1,'unit_price':line,'total_price':line}); }
  }
  Future<void> capture(String id,DateTime date)=>db.transaction((tx)=>CommissionLedger.capture(tx,id,date));
  Future<void> closeSeptember() async{await invoice('a',total:1000000,line:1000000);await capture('a',DateTime(2026,9,15));await repo.closePeriod('2026-09');}

  test('LAN checkout rollback and replay preserve one snapshot with employee attribution',()async{
    final stamp=now.toIso8601String();
    await db.insert('services',{'id':'svc','name':'Cắt','category':'Tóc','duration_minutes':30,
      'price':100000,'created_at':stamp,'updated_at':stamp});
    final bills=SqliteBillingSessionsRepository(SalonDatabase.instance);
    final session=await bills.createWalkInSession();
    await bills.selectCustomer(session.id,'cust');
    final draft=await bills.addService(session.id,'svc',employeeId:'emp');
    expect(draft.lines.single.employeeId,'emp');
    final engine=LanWriteEngine(SalonDatabase.instance);
    final phone=PairedPhone('a'*64,'Phone',PhoneAccess.approved,DateTime.utc(2026),
      canReadSalon:true,writeRole:PhoneWriteRole.owner);
    final command=LanWriteCommand(commandId:'checkout',operation:LanWriteOperation.sessionCheckout,
      expectedEpoch:SalonDatabase.instance.runtimeEpoch,targetId:session.id,
      expectedRevision:await engine.revision(db,'session',session.id),payload:{});
    await expectLater(engine.execute(phone,command,(scope)async{
      await SqliteInvoicesRepository(scope,null,session.id).checkoutInvoice();
      throw StateError('fixture after checkout');
    }),throwsA(isA<PairingFailure>()));
    expect(await db.query('commission_entries'),isEmpty);
    final first=await engine.execute(phone,command,(scope)async{
      final invoices=SqliteInvoicesRepository(scope,null,session.id);
      await invoices.checkoutInvoice();
      return LanMutationTarget(invoices.lastArchivedInvoiceId!,'invoice');
    });
    expect((await db.query('commission_entries')).single['amount'],10000);
    await db.update('employees',{'commission_rate':0.7});
    final replay=await engine.execute(phone,command,(_)async=>throw StateError('must not run'));
    expect(replay.id,first.id);expect(await db.query('commission_entries'),hasLength(1));
    final invoices=SqliteInvoicesRepository(SalonDatabase.instance);
    await invoices.refundInvoice(first.id,reason:'Test');
    expect((await db.query('commission_entries',where:"kind='reversal'")).single['amount'],-10000);
  });

  test('rate edits require Owner, validate finite precision/range and leave snapshots unchanged',()async{
    await invoice('a');await capture('a',DateTime(2026,9,15));
    final employees=SqliteEmployeesRepository(SalonDatabase.instance,const FakeSalonDataSource(),security:security);
    EmployeeUpsertInput input(String rate)=>EmployeeUpsertInput(fullName:'Thợ A',role:'Stylist',
      status:'Đang làm việc',phone:'',shift:'',specialty:'',commissionLabel:rate,todaySchedule:'',
      servicesDone:0,monthlyRevenue:'',rating:'',note:'');
    for(final bad in ['-1%','101%','NaN','Infinity','10.123%','abc']){
      await expectLater(employees.saveEmployee(input(bad),existingId:'emp'),throwsArgumentError);
    }
    await security.configureOwnerPin('1234');security.lockOwnerSession();
    await expectLater(employees.saveEmployee(input('25%'),existingId:'emp'),throwsStateError);
    await security.unlockOwner('1234');await employees.saveEmployee(input('25%'),existingId:'emp');
    expect((await db.query('employees')).single['commission_rate'],0.25);
    expect((await db.query('commission_entries')).single['rate_bps'],1000);
    expect(await db.query('audit_events',where:"action='commission_rate' AND result='success'"),hasLength(1));
  });

  test('net allocation includes retail weight; snapshots rate and excludes retail commission',()async{
    await invoice('a',total:90001,line:100000,retail:true);
    await capture('a',DateTime(2026,9,15));
    final original=(await db.query('commission_entries')).single;
    expect(original['basis'],45001);expect(original['amount'],4500);expect(original['rate_bps'],1000);
    await db.update('employees',{'commission_rate':0.25});
    await capture('a',DateTime(2026,9,15));
    expect((await db.query('commission_entries')).single,original);
    await invoice('b',total:100005,line:100005);
    await capture('b',DateTime(2026,9,16));
    expect((await db.query('commission_entries',where:'invoice_id=?',whereArgs:['b'])).single['amount'],25001);
    expect(await db.rawQuery('PRAGMA foreign_key_check'),isEmpty);
  });
  test('full refund uses original money once, next month across year, without changing paid proof',()async{
    await invoice('a',paid:DateTime(2026,12,20));await capture('a',DateTime(2026,12,20));
    await db.update('employees',{'commission_rate':0.7});
    await db.transaction((tx)=>CommissionLedger.reverse(tx,'a',DateTime(2026,12,25)));
    await db.transaction((tx)=>CommissionLedger.reverse(tx,'a',DateTime(2026,12,25)));
    final reverse=(await db.query('commission_entries',where:"kind='reversal'")).single;
    expect(reverse['period'],'2027-01');expect(reverse['amount'],-10000);expect(reverse['rate_bps'],1000);
    await expectLater(db.update('commission_entries',{'amount':0}),throwsA(isA<DatabaseException>()));
  });
  test('close requires completed month and chronological order, is idempotent, creates no cash',()async{
    await invoice('a');await capture('a',DateTime(2026,9,15));
    await invoice('b',paid:DateTime(2026,8,15));await capture('b',DateTime(2026,8,15));
    await expectLater(repo.closePeriod('2026-09'),throwsStateError);
    await expectLater(repo.closePeriod('2026-10'),throwsStateError);
    await repo.closePeriod('2026-08');await repo.closePeriod('2026-09');await repo.closePeriod('2026-09');
    expect(await db.query('commission_periods'),hasLength(2));expect(await db.query('cash_movements'),isEmpty);
    await expectLater(capture('a',DateTime(2026,9,15)),completes);
    // A new transaction after a closed month is allocated to the next open month.
    await invoice('c');await capture('c',DateTime(2026,9,15));
    expect((await db.query('commission_entries',where:'invoice_id=?',whereArgs:['c'])).single['period'],'2026-10');
  });
  test('partial cash payout linked to open shift, transfer remainder and exact replay do not pay twice',()async{
    await closeSeptember();
    await expectLater(repo.pay(requestId:'cash',employeeId:'emp',amount:40000,method:'cash'),throwsStateError);
    expect(await repo.pendingPayout(),isNotNull);
    await db.insert('cashier_shifts',{'id':'shift','opening_cash':200000,'opened_at':now.toIso8601String()});
    await repo.pay(requestId:'cash',employeeId:'emp',amount:40000,method:'cash');
    await repo.pay(requestId:'cash',employeeId:'emp',amount:40000,method:'cash');
    expect(await db.query('cash_movements'),hasLength(1));expect(await repo.pendingPayout(),isNull);
    await repo.pay(requestId:'transfer',employeeId:'emp',amount:60000,method:'transfer',reference:'bank-001');
    final account=(await repo.fetch()).accounts.single;
    expect(account.settled,100000);expect(account.paid,100000);expect(account.balance,0);
    await expectLater(repo.pay(requestId:'excess',employeeId:'emp',amount:1,method:'transfer',reference:'bank-002'),throwsStateError);
    await repo.resolvePendingPayout('excess');
    await expectLater(db.delete('cash_movements'),throwsA(isA<DatabaseException>()));
    await expectLater(db.update('commission_payouts',{'amount':1}),throwsA(isA<DatabaseException>()));
  });
  test('audit insert failure rolls back payout and cash together, retains retry ID',()async{
    await closeSeptember();
    await db.insert('cashier_shifts',{'id':'shift','opening_cash':200000,'opened_at':now.toIso8601String()});
    await db.execute("CREATE TRIGGER fail_commission_audit BEFORE INSERT ON audit_events WHEN NEW.action='commission_pay' BEGIN SELECT RAISE(ABORT,'fixture'); END");
    await expectLater(repo.pay(requestId:'retry',employeeId:'emp',amount:40000,method:'cash'),throwsA(isA<DatabaseException>()));
    expect(await db.query('commission_payouts'),isEmpty);expect(await db.query('cash_movements'),isEmpty);
    expect((await repo.pendingPayout())!['requestId'],'retry');
    await db.execute('DROP TRIGGER fail_commission_audit');
    await repo.pay(requestId:'retry',employeeId:'emp',amount:40000,method:'cash');
    expect((await repo.fetch()).accounts.single.paid,40000);
  });
  test('owner protection enforced in repository for close and pay',()async{
    await invoice('a');await capture('a',DateTime(2026,9,15));
    await security.configureOwnerPin('1234');security.lockOwnerSession();
    await expectLater(repo.closePeriod('2026-09'),throwsStateError);
    expect(await db.query('commission_periods'),isEmpty);
    expect(await security.unlockOwner('1234'),isTrue);await repo.closePeriod('2026-09');security.lockOwnerSession();
    await expectLater(repo.pay(requestId:'denied',employeeId:'emp',amount:1000,method:'transfer',reference:'r'),throwsStateError);
    expect(await db.query('commission_payouts'),isEmpty);
    expect(await repo.pendingPayout(),isNull);
  });
  test('concurrent partial payouts never exceed settled balance and preserve unresolved request',()async{
    await closeSeptember();
    final results=await Future.wait([
      repo.pay(requestId:'one',employeeId:'emp',amount:60000,method:'transfer',reference:'r1').then((_)=>true,onError:(_)=>false),
      repo.pay(requestId:'two',employeeId:'emp',amount:60000,method:'transfer',reference:'r2').then((_)=>true,onError:(_)=>false)]);
    expect(results.where((v)=>v),hasLength(1));expect((await repo.fetch()).accounts.single.paid,60000);
  });
  test('reversal after fully paid creates negative balance at next close and offsets future commission',()async{
    await closeSeptember();
    await repo.pay(requestId:'paid',employeeId:'emp',amount:100000,method:'transfer',reference:'r');
    await db.transaction((tx)=>CommissionLedger.reverse(tx,'a',DateTime(2026,10,5)));
    now=DateTime(2026,12,1);await repo.closePeriod('2026-11');
    expect((await repo.fetch()).accounts.single.balance,-100000);
    await invoice('b',total:2000000,line:2000000,paid:DateTime(2026,12,15));
    await capture('b',DateTime(2026,12,15));now=DateTime(2027,1,1);await repo.closePeriod('2026-12');
    expect((await repo.fetch()).accounts.single.balance,100000);
  });
  test('schema20 migration never invents legacy money and leaves old paid invoice untouched',()async{
    await invoice('old');
    for(final table in ['commission_payouts','commission_entries','commission_periods']){await db.execute('DROP TABLE $table');}
    await db.execute('DROP TRIGGER commission_cash_no_update');await db.execute('DROP TRIGGER commission_cash_no_delete');
    await db.setVersion(20);await SalonDatabase.instance.close();
    db=await SalonDatabase.instance.initialize(preserveExistingTestDatabase:true);
    expect(await db.getVersion(),21);expect(await db.query('commission_entries'),isEmpty);
    expect((await db.query('invoices')).single['id'],'old');
    expect(await db.rawQuery('PRAGMA foreign_key_check'),isEmpty);
  });
  test('backup restore and restart keep snapshots, proof and pending request; replay cannot pay twice',()async{
    await closeSeptember();
    await repo.pay(requestId:'paid',employeeId:'emp',amount:40000,method:'transfer',reference:'r');
    await expectLater(repo.pay(requestId:'pending',employeeId:'emp',amount:90000,method:'transfer',reference:'r2'),throwsStateError);
    final entries=await db.query('commission_entries');
    const backup=BackupService();
    final saved=await backup.createBackup();expect(saved.success,isTrue,reason:saved.message);
    await repo.resolvePendingPayout('pending');
    await db.update('employees',{'commission_rate':0.9});
    final restored=await backup.restoreFromBackup(saved.filePath!);expect(restored.success,isTrue,reason:restored.message);
    db=await SalonDatabase.instance.database;
    expect(await db.query('commission_entries'),entries);expect((await repo.fetch()).accounts.single.paid,40000);
    expect((await repo.pendingPayout())!['requestId'],'pending');
    await repo.resolvePendingPayout('pending');
    await SalonDatabase.instance.close();await SalonDatabase.instance.initialize(preserveExistingTestDatabase:true);
    await repo.pay(requestId:'paid',employeeId:'emp',amount:40000,method:'transfer',reference:'r');
    expect((await repo.fetch()).accounts.single.paid,40000);
  });
}
