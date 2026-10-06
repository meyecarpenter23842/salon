import 'dart:async';
import 'package:flutter/material.dart';
import 'package:salonmanager/core/lan/lan_contract.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_read_client.dart';
import 'package:salonmanager/core/lan/lan_read_models.dart';
import 'package:salonmanager/core/lan/lan_workflow_client.dart';
import 'package:salonmanager/core/lan/lan_workflow_models.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/features/companion/companion_credential_store.dart';
import 'package:salonmanager/features/companion/companion_command_controller.dart';
import 'package:salonmanager/features/companion/companion_workspace.dart';

class MobileTestStore implements CompanionCredentialStore {
  CompanionCredential value = CompanionCredential('b' * 64, 'c' * 64);
  @override Future<CompanionCredential?> read() async => value;
  @override Future<void> write(CompanionCredential next) async { value = next; }
  @override Future<void> clear() async {}
}
class MobileTestReader implements SalonReadClient {
  final queries = <SalonReadQuery>[];
  bool fail = false;
  @override Future<SalonReadPage> read(LanConnection c, String t, SalonReadQuery query) async {
    queries.add(query);
    if (fail) { throw StateError('private backend data'); }
    return SalonReadPage(salonDate: '2026-10-06', records: [
      SalonReadRecord(id: '${query.kind.name}-1', title: query.kind == SalonReadKind.appointments ? '09:00 · Khách Lan' : 'Khách Lan',
        subtitle: query.kind == SalonReadKind.appointments ? 'Gội dưỡng · Đã đặt' : '0901234567 · Member',
        fields: query.id == null ? const {} : {'Điện thoại': '0901234567', 'Hạng khách': 'Member', 'Ghi chú': 'Khách thích yên tĩnh'}),
    ]);
  }
}
class MobileTestClient implements LanWorkflowClient {
  final sent = <LanWriteCommand>[];
  final searches = <String>[];
  bool conflict = false, unavailable = false, resolved = false;
  Completer<LanWriteResult>? sending;
  @override Future<LanCatalogPage> catalog(LanConnection c, String t, String k, String q, int o) async {
    searches.add('$k|$q|$o');
    return LanCatalogPage([LanCatalogItem('$k-${o == 0 ? 1 : 2}', switch(k) {
      'customers' => 'Khách Lan', 'services' => 'Gội dưỡng', _ => 'Thợ An',
    }, 'Thông tin từ desktop')], 'desktop-epoch', k == 'services' && o == 0 ? 25 : null);
  }
  @override Future<LanEditorSnapshot> editor(LanConnection c, String t, String kind, String? id) async =>
    LanEditorSnapshot(kind: kind, id: id, epoch: 'desktop-epoch', revision: id == null ? 0 : 1,
      values: kind == 'appointment' ? {
        'customerId': id == null ? '' : 'customers-1', 'customerLabel': 'Khách Lan',
        'serviceIds': id == null ? <String>[] : ['services-1'], 'serviceLabels': {'services-1': 'Gội dưỡng'},
        'employeeId': id == null ? '' : 'employees-1', 'employeeLabel': 'Thợ An',
        'day': '2026-10-06', 'time': '09:00', 'status': 'Đã đặt', 'durationMinutes': 90, 'slotLabel': '', 'note': '',
      } : {'fullName': id == null ? '' : 'Khách Lan', 'phone': id == null ? '' : '0901234567', 'email': '', 'tier': 'Member',
        'favoriteService': '', 'hairProfile': '', 'note': ''});
  @override Future<LanWriteResult> send(LanConnection c, String t, LanWriteCommand command) async {
    sent.add(command);
    if (conflict) { throw const PairingFailure(LanErrorCode.revisionConflict); }
    if (unavailable) { throw const PairingFailure(LanErrorCode.unavailable); }
    if (sending != null) { return sending!.future; }
    return LanWriteResult(id: command.targetId ?? 'new-1', type: command.operation.resourceType, revision: 2);
  }
  @override Future<LanWriteResult?> result(LanConnection c, String t, String id) async => resolved ? LanWriteResult(id: sent.last.targetId ?? 'new-1', type: sent.last.operation.resourceType, revision: 2) : null;
}
Future<CompanionCommandController> showMobile(WidgetTester tester, MobileTestReader reader, MobileTestClient client,
    {PhoneWriteRole role = PhoneWriteRole.staff, double textScale = 1}) async {
  final connection = LanConnection('https://192.168.1.20:8743/api/staff/v1', 'b' * 64);
  final store = MobileTestStore();
  final commands = CompanionCommandController(connection: connection, client: client,
    store: store, credential: store.value, onCredential: (_) {});
  await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
    home: CompanionWorkspace(connection: connection, readClient: reader,
      client: client, commands: commands, role: role, onDenied: () {})));
  await tester.pumpAndSettle();
  return commands;
}
Future<void> tapMobile(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key)); await tester.ensureVisible(finder);
  await tester.pumpAndSettle(); await tester.tap(finder); await tester.pumpAndSettle();
}
void main() {
  testWidgets('five destinations keep customer search and return from profile on narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360,640); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final reader = MobileTestReader(); final commands = await showMobile(tester, reader, MobileTestClient());
    expect(find.byKey(const Key('mobile-tab-more')), findsOneWidget);
    await tapMobile(tester, 'mobile-tab-customers');
    await tester.enterText(find.byKey(const Key('salon-customer-search')), '090123');
    await tapMobile(tester, 'salon-search');
    expect(reader.queries.last.query, '090123');
    await tapMobile(tester, 'salon-record-customers-1');
    expect(find.text('Hồ sơ khách hàng'), findsOneWidget);
    await tester.pageBack(); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('salon-customer-search'))).controller!.text, '090123');
    await tapMobile(tester, 'mobile-tab-appointments'); await tapMobile(tester, 'mobile-tab-customers');
    expect(tester.widget<TextField>(find.byKey(const Key('salon-customer-search'))).controller!.text, '090123');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); commands.dispose();
  });
  testWidgets('read-only navigation hides create, keeps date picker and large text fits', (tester) async {
    tester.view.physicalSize = const Size(360,640); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final commands = await showMobile(tester, MobileTestReader(), MobileTestClient(), role: PhoneWriteRole.none, textScale: 1.5);
    await tapMobile(tester, 'mobile-tab-customers');
    expect(find.byKey(const Key('write-new-customer')), findsNothing);
    await tapMobile(tester, 'mobile-tab-appointments');
    expect(find.byKey(const Key('write-new-appointment')), findsNothing);
    expect(find.byKey(const Key('salon-pick-day')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); commands.dispose();
  });
}
