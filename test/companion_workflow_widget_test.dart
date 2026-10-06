import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_pairing_client.dart';
import 'package:salonmanager/features/companion/companion_access_panel.dart';
import 'package:salonmanager/core/lan/lan_read_client.dart';
import 'package:salonmanager/core/lan/lan_read_models.dart';
import 'package:salonmanager/core/lan/lan_workflow_client.dart';
import 'package:salonmanager/core/lan/lan_workflow_models.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/features/companion/companion_command_controller.dart';
import 'package:salonmanager/features/companion/companion_credential_store.dart';
import 'package:salonmanager/features/companion/companion_workspace.dart';
import 'package:salonmanager/features/companion/companion_bill_workspace.dart';

class _Store implements CompanionCredentialStore {
  CompanionCredential value = CompanionCredential('b' * 64, 'c' * 64);
  @override Future<CompanionCredential?> read() async => value;
  @override Future<void> write(CompanionCredential next) async { value = next; }
  @override Future<void> clear() async {}
}
class _Reader implements SalonReadClient {
  @override Future<SalonReadPage> read(LanConnection c, String token, SalonReadQuery query) async =>
    const SalonReadPage(salonDate: '2026-10-06', records: []);
}
class _Client implements LanWorkflowClient {
  final sent = <LanWriteCommand>[];
  int revision = 1;
  @override Future<LanEditorSnapshot> editor(LanConnection c, String token, String kind, String? id) async =>
    LanEditorSnapshot(kind: kind, epoch: 'desktop-epoch', revision: id == null ? 0 : revision,
      id: id, values: kind == 'customer' ? {'fullName': '', 'phone': '', 'email': '', 'tier': 'Standard',
        'favoriteService': '', 'hairProfile': '', 'note': ''} : kind == 'appointment' ?
      {'customerId': '', 'serviceIds': <String>[], 'employeeId': '', 'day': '2026-10-06', 'time': '09:00',
        'status': 'Đã đặt', 'durationMinutes': 60, 'slotLabel': '', 'note': '',
        'customerLabel': '', 'employeeLabel': '', 'serviceLabels': <String, String>{}} :
      {'customerId': 'customer-1', 'customerLabel': 'Khách bill', 'appointmentId': null,
        'subtotal': 100000, 'discountAmount': 0, 'totalAmount': 100000,
        'paymentMethod': 'Tiền mặt', 'payments': [{'method': 'Tiền mặt', 'amount': 100000}],
        'lines': [{'id': 'line-1', 'title': 'Dịch vụ', 'quantity': 1, 'unitPrice': 100000,
          'discountAmount': 0, 'totalPrice': 100000, 'employeeId': null, 'isService': true}]});
  @override Future<LanCatalogPage> catalog(LanConnection c, String token, String kind, String q, int offset) async =>
    LanCatalogPage([LanCatalogItem(kind == 'customers' ? 'customer-1' : kind == 'employees' ? 'employee-1' :
      kind == 'sessions' ? 'session-1' : 'service-1', kind == 'sessions' ? 'Khách bill' : 'Mục chọn $kind', '')],
      'desktop-epoch', null);
  @override Future<LanWriteResult> send(LanConnection c, String token, LanWriteCommand command) async {
    sent.add(command); revision++;
    return LanWriteResult(id: command.operation == LanWriteOperation.sessionCheckout ? 'invoice-1' :
      command.targetId ?? 'new-1', type: command.operation == LanWriteOperation.sessionCheckout ? 'invoice' :
      command.operation.resourceType, revision: revision);
  }
  @override Future<LanWriteResult?> result(LanConnection c, String token, String id) async => null;
}

class _Pairing implements LanPairingClient {
  PhoneAccess state = PhoneAccess.approved;
  PairedPhone get phone => PairedPhone('a' * 64, 'Phone', state, DateTime.utc(2026),
    canReadSalon: state == PhoneAccess.approved, writeRole: state == PhoneAccess.approved ? PhoneWriteRole.cashier : PhoneWriteRole.none);
  @override Future<PairedPhone> status(LanConnection c, String token) async => phone;
  @override Future<PairedPhone> bootstrap(LanConnection c, String token) async => phone;
  @override Future<PairedPhone> request(LanConnection c, String code, String name, String token) async => phone;
}

void main() {
  final connection = LanConnection('https://192.168.1.20:8743/api/staff/v1', 'b' * 64);
  Future<CompanionCommandController> show(WidgetTester tester, _Client client, PhoneWriteRole role) async {
    final store = _Store();
    final commands = CompanionCommandController(connection: connection, client: client,
      store: store, credential: store.value, onCredential: (_) {});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: CompanionBillWorkspace(connection: connection, readClient: _Reader(), client: client,
        commands: commands, role: role, onDenied: () {})))));
    await tester.pumpAndSettle(); return commands;
  }
  Future<void> tap(WidgetTester tester, String key) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final finder = find.byKey(Key(key)); await tester.ensureVisible(finder); await tester.pumpAndSettle();
    await tester.tap(finder); await tester.pumpAndSettle();
  }
  testWidgets('narrow Android customer and appointment forms send selected desktop ids and explicit date', (tester) async {
    tester.view.physicalSize = const Size(360, 640); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final client = _Client(); final commands = await show(tester, client, PhoneWriteRole.staff);
    await tap(tester, 'write-new-customer');
    await tester.enterText(find.byKey(const Key('write-fullName')), 'Lan');
    await tester.enterText(find.byKey(const Key('write-phone')), '0901234567');
    await tap(tester, 'write-save');
    expect(client.sent.single.operation, LanWriteOperation.customerCreate);
    expect(client.sent.single.payload['fullName'], 'Lan');
    await tap(tester, 'write-new-appointment');
    await tap(tester, 'write-pick-customer'); await tap(tester, 'catalog-customer-1');
    await tap(tester, 'write-pick-employee'); await tap(tester, 'catalog-employee-1');
    await tap(tester, 'write-pick-services'); await tap(tester, 'catalog-service-1');
    await tester.ensureVisible(find.text('Đóng danh sách chọn')); await tester.pump();
    await tester.tap(find.text('Đóng danh sách chọn')); await tester.pumpAndSettle();
    await tap(tester, 'write-save');
    expect(client.sent.last.operation, LanWriteOperation.appointmentCreate);
    expect(client.sent.last.payload['customerId'], 'customer-1');
    expect(client.sent.last.payload['employeeId'], 'employee-1');
    expect(client.sent.last.payload['serviceIds'], ['service-1']);
    expect(client.sent.last.payload['day'], '2026-10-06');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); commands.dispose();
  });
  testWidgets('cashier bill requires explicit confirmation; staff has no checkout and read-only has no create', (tester) async {
    final client = _Client(); var commands = await show(tester, client, PhoneWriteRole.cashier);
    await tap(tester, 'write-bills'); await tap(tester, 'catalog-session-1');
    expect(find.byKey(const Key('write-discount')), findsNothing);
    await tap(tester, 'bill-payment');
    expect(client.sent.last.operation, LanWriteOperation.sessionPayment);
    await tap(tester, 'bill-checkout');
    expect(client.sent.where((c) => c.operation == LanWriteOperation.sessionCheckout), isEmpty);
    await tap(tester, 'bill-confirm-checkout');
    expect(client.sent.where((c) => c.operation == LanWriteOperation.sessionCheckout), hasLength(1));
    expect(find.textContaining('Đã thanh toán'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); commands.dispose();
    commands = await show(tester, _Client(), PhoneWriteRole.staff);
    await tap(tester, 'write-bills'); await tap(tester, 'catalog-session-1');
    expect(find.byKey(const Key('bill-checkout')), findsNothing);
    await tester.pumpWidget(const SizedBox()); commands.dispose();
    commands = await show(tester, _Client(), PhoneWriteRole.none);
    expect(find.byKey(const Key('write-new-customer')), findsNothing);
    expect(find.byKey(const Key('write-new-bill')), findsNothing);
    await tester.pumpWidget(const SizedBox()); commands.dispose();
  });
  testWidgets('revoked uncertain checkout cannot forget or resend; explicit desktop review clears it', (tester) async {
    final store = _Store();
    store.value = store.value.withPending(LanWriteCommand(commandId: 'uncertain-checkout',
      operation: LanWriteOperation.sessionCheckout, expectedEpoch: 'desktop-epoch',
      targetId: 'session-1', expectedRevision: 1, payload: {}));
    final client = _Client(); final pair = _Pairing();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      CompanionAccessPanel(connection: connection, client: pair, store: store,
        readClient: _Reader(), workflowClient: client, onAccess: (_) {}))));
    await tester.pumpAndSettle();
    await tap(tester, 'mobile-tab-more');
    expect((tester.widget<TextButton>(find.byKey(const Key('companion-forget')))).onPressed, isNull);
    pair.state = PhoneAccess.revoked;
    await tester.pump(const Duration(seconds: 5)); await tester.pumpAndSettle();
    expect(find.byType(CompanionWorkspace), findsNothing);
    expect((tester.widget<TextButton>(find.byKey(const Key('write-reviewed-discard')))).onPressed, isNull);
    await tap(tester, 'write-review-confirmed'); await tap(tester, 'write-reviewed-discard');
    expect(store.value.pendingCommand, isNull); expect(client.sent, isEmpty);
    expect((tester.widget<TextButton>(find.byKey(const Key('companion-forget')))).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

}
