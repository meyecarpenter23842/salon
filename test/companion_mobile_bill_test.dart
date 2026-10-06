import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_pairing_client.dart';
import 'package:salonmanager/features/companion/companion_access_panel.dart';
import 'package:salonmanager/features/companion/companion_catalog_picker.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/features/companion/companion_bill_editors.dart';
import 'package:salonmanager/features/companion/companion_command_controller.dart';
import 'package:salonmanager/features/companion/companion_mobile_bill.dart';
import 'package:salonmanager/features/companion/companion_theme.dart';
import 'package:salonmanager/features/companion/companion_workspace.dart';
import 'support/mobile_bill_fixture.dart';

final billConnection = LanConnection('https://192.168.1.20:8743/api/staff/v1', 'b' * 64);
Future<void> billTap(WidgetTester tester, String key) async {
  FocusManager.instance.primaryFocus?.unfocus(); await tester.pumpAndSettle();
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 180, scrollable: find.byType(Scrollable).last, maxScrolls: 30);
  }
  await tester.ensureVisible(finder); await tester.pumpAndSettle();
  await tester.tap(finder); await tester.pumpAndSettle();
}
Future<CompanionCommandController> mountBill(WidgetTester tester, BillTestClient client,
    {PhoneWriteRole role = PhoneWriteRole.cashier, BillTestStore? store, bool workspace = false, double scale = 1}) async {
  final storage = store ?? BillTestStore();
  final commands = CompanionCommandController(connection: billConnection, client: client,
    store: storage, credential: storage.value, onCredential: (_) {});
  await tester.pumpWidget(MaterialApp(locale: const Locale('vi'), supportedLocales: const [Locale('vi'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates, theme: companionTheme(),
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: workspace ? CompanionWorkspace(connection: billConnection, readClient: client, client: client,
      commands: commands, role: role, onDenied: () {}) : CompanionMobileBill(connection: billConnection,
      readClient: client, client: client, commands: commands, role: role, onDenied: () {}, id: 'bill-a')));
  await tester.pumpAndSettle(); return commands;
}
class _BillPairing implements LanPairingClient {
  PhoneAccess state = PhoneAccess.approved;
  PairedPhone get phone => PairedPhone('a' * 64, 'Phone', state, DateTime.utc(2026),
    canReadSalon: state == PhoneAccess.approved, writeRole: PhoneWriteRole.cashier);
  @override Future<PairedPhone> status(LanConnection c, String token) async => phone;
  @override Future<PairedPhone> bootstrap(LanConnection c, String token) async => phone;
  @override Future<PairedPhone> request(LanConnection c, String code, String name, String token) async => phone;
}
void main() {
  testWidgets('production bill lists keep filters; atomic edit targets A and switching to B keeps its data', (tester) async {
    final client = BillTestClient(); final commands = await mountBill(tester, client, workspace: true, role: PhoneWriteRole.owner);
    await billTap(tester, 'mobile-tab-invoices');
    await tester.enterText(find.byKey(const Key('bill-list-search-0')), 'bill-');
    await billTap(tester, 'bill-list-find'); expect(client.searches.last, 'sessions|bill-|0');
    await billTap(tester, 'bill-list-bill-a'); await billTap(tester, 'bill-edit-line-service');
    expect(find.byKey(const Key('bill-line-price')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('bill-line-quantity')), '2');
    await tester.enterText(find.byKey(const Key('bill-line-price')), '130000');
    await billTap(tester, 'bill-line-save');
    expect(client.sent.single.operation, LanWriteOperation.sessionUpdateLine);
    expect(client.sent.single.targetId, 'bill-a'); expect(client.sent.single.expectedRevision, 1);
    expect(client.sent.single.payload, {'lineId': 'line-service', 'quantity': 2, 'employeeId': 'employees-1', 'unitPrice': 130000});
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('bill-list-search-0'))).controller!.text, 'bill-');
    await billTap(tester, 'bill-list-bill-b'); await billTap(tester, 'bill-edit-line-service');
    expect(tester.widget<TextFormField>(find.byKey(const Key('bill-line-quantity'))).controller!.text, '1');
    expect(client.sessions['bill-b']!['totalAmount'], 150000);
    expect(tester.takeException(), isNull); await tester.pumpWidget(const SizedBox()); commands.dispose();
  });

  testWidgets('cashier default single method; split sums validate, review locks double taps and receipt follows', (tester) async {
    final client = BillTestClient(); final commands = await mountBill(tester, client);
    await billTap(tester, 'bill-edit-payment');
    expect(find.byKey(const Key('bill-payment-Tiền mặt')), findsNothing);
    await billTap(tester, 'bill-payment-split');
    await tester.enterText(find.byKey(const Key('bill-payment-Tiền mặt')), '50000');
    await tester.enterText(find.byKey(const Key('bill-payment-Chuyển khoản')), '50000');
    await billTap(tester, 'bill-payment-done');
    expect(find.byType(CompanionBillPaymentEditor), findsOneWidget); expect(client.sent, isEmpty);
    await tester.enterText(find.byKey(const Key('bill-payment-Chuyển khoản')), '100000');
    await billTap(tester, 'bill-payment-done');
    final button = find.byKey(const Key('bill-checkout'));
    await tester.tap(button); await tester.tap(button); await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget); expect(client.sent, isEmpty);
    expect(find.text('Xác nhận thanh toán'), findsNWidgets(2));
    await billTap(tester, 'bill-confirm-checkout');
    expect(client.sent.map((c) => c.operation), [LanWriteOperation.sessionPayment, LanWriteOperation.sessionCheckout]);
    expect(client.sent.first.payload['payments'], [{'method': 'Tiền mặt', 'amount': 50000}, {'method': 'Chuyển khoản', 'amount': 100000}]);
    expect(client.sent.last.expectedRevision, 2); expect(client.invoices, 1);
    expect(find.text('Thanh toán thành công'), findsOneWidget); expect(find.textContaining('Mã hóa đơn: invoice-1'), findsOneWidget);
    expect(find.byKey(const Key('bill-checkout')), findsNothing);
    expect(tester.takeException(), isNull); await tester.pumpWidget(const SizedBox()); commands.dispose();
  });

  testWidgets('uncertain checkout survives recreation and resolves receipt without a second checkout', (tester) async {
    final store = BillTestStore(), client = BillTestClient()..loseCheckout = true;
    var commands = await mountBill(tester, client, store: store);
    await billTap(tester, 'bill-checkout'); await billTap(tester, 'bill-confirm-checkout');
    expect(client.invoices, 1); expect(store.value.pendingCommand?.operation, LanWriteOperation.sessionCheckout);
    final commandId = store.value.pendingCommand!.commandId;
    expect(find.textContaining('Kết quả thanh toán chưa rõ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); commands.dispose();
    commands = await mountBill(tester, client, store: store);
    expect(find.text('Bill đã thanh toán'), findsOneWidget);
    await billTap(tester, 'write-check-result');
    expect(find.text('Thanh toán thành công'), findsOneWidget); expect(store.value.pendingCommand, isNull);
    expect(client.sent, hasLength(1)); expect(client.journal[commandId]!.id, 'invoice-1');
    await tester.pumpWidget(const SizedBox()); commands.dispose();
  });

  testWidgets('conflict retains line input and blocks resave until a fresh bill is loaded', (tester) async {
    final client = BillTestClient(); final commands = await mountBill(tester, client);
    await billTap(tester, 'bill-edit-line-service');
    await tester.enterText(find.byKey(const Key('bill-line-quantity')), '3');
    client.conflict = true; await billTap(tester, 'bill-line-save');
    expect(tester.widget<TextFormField>(find.byKey(const Key('bill-line-quantity'))).controller!.text, '3');
    expect(tester.widget<FilledButton>(find.byKey(const Key('bill-line-save'))).onPressed, isNull);
    expect(commands.pending, isNull);
    await tester.binding.handlePopRoute(); await tester.pumpAndSettle();
    expect(find.text('Bỏ thay đổi chưa lưu?'), findsOneWidget);
    await billTap(tester, 'bill-keep-editing'); expect(find.byType(CompanionBillLineEditor), findsOneWidget);
    client.conflict = false;
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle(); await billTap(tester, 'bill-discard');
    await billTap(tester, 'bill-edit-line-service');
    expect(tester.widget<TextFormField>(find.byKey(const Key('bill-line-quantity'))).controller!.text, '1');
    expect(client.sent, hasLength(1)); expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox()); commands.dispose();
  });

  testWidgets('payment draft protects refresh/back; readonly and staff cannot escalate checkout or price', (tester) async {
    final client = BillTestClient(); var commands = await mountBill(tester, client);
    await billTap(tester, 'bill-edit-payment'); await billTap(tester, 'bill-method-Thẻ'); await billTap(tester, 'bill-payment-done');
    await billTap(tester, 'bill-reload'); expect(find.text('Bỏ thay đổi chưa lưu?'), findsOneWidget);
    await billTap(tester, 'bill-keep-editing'); expect(client.sent, isEmpty);
    await tester.binding.handlePopRoute(); await tester.pumpAndSettle();
    expect(find.text('Bỏ thay đổi chưa lưu?'), findsOneWidget); await billTap(tester, 'bill-keep-editing');
    await tester.pumpWidget(const SizedBox()); commands.dispose();
    commands = await mountBill(tester, BillTestClient(), role: PhoneWriteRole.staff);
    expect(find.byKey(const Key('bill-checkout')), findsNothing); expect(find.byKey(const Key('bill-edit-payment')), findsNothing);
    await billTap(tester, 'bill-edit-line-service'); expect(find.byKey(const Key('bill-line-price')), findsNothing);
    await tester.pumpWidget(const SizedBox()); commands.dispose();
    commands = await mountBill(tester, BillTestClient(), role: PhoneWriteRole.none);
    expect(find.byKey(const Key('bill-edit-line-service')), findsNothing); expect(find.byKey(const Key('bill-add-product')), findsNothing);
    await tester.pumpWidget(const SizedBox()); commands.dispose();
  });

  testWidgets('narrow large text, line keyboard, negative-stock warning and receipt read failure remain usable', (tester) async {
    tester.view.physicalSize = const Size(360, 640); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final client = BillTestClient(); final commands = await mountBill(tester, client, role: PhoneWriteRole.owner, scale: 1.5);
    await billTap(tester, 'bill-edit-line-service');
    tester.view.viewInsets = const FakeViewPadding(bottom: 260); await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const Key('bill-line-save')));
    expect(rect.bottom, lessThanOrEqualTo(380));
    expect(tester.takeException(), isNull); tester.view.resetViewInsets(); await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton)); await tester.pumpAndSettle();
    final warning = find.byKey(const Key('bill-stock-line-product')); await tester.ensureVisible(warning); await tester.pumpAndSettle();
    expect(tester.widget<Text>(warning).style!.color, Colors.red);
    client.failReceipt = true; await billTap(tester, 'bill-checkout'); await billTap(tester, 'bill-confirm-checkout');
    expect(find.text('Thanh toán thành công'), findsOneWidget);
    expect(find.textContaining('không thanh toán lại'), findsOneWidget); expect(client.invoices, 1);
    expect(tester.takeException(), isNull); await tester.pumpWidget(const SizedBox()); commands.dispose();
  });
  testWidgets('unknown payment setup resolves without automatically checking out', (tester) async {
    final client = BillTestClient()..losePayment = true, store = BillTestStore();
    final commands = await mountBill(tester, client, store: store);
    await billTap(tester, 'bill-edit-payment'); await billTap(tester, 'bill-method-Thẻ'); await billTap(tester, 'bill-payment-done');
    await billTap(tester, 'bill-checkout'); await billTap(tester, 'bill-confirm-checkout');
    expect(store.value.pendingCommand?.operation, LanWriteOperation.sessionPayment);
    expect(client.invoices, 0); expect(client.sent, hasLength(1));
    await billTap(tester, 'write-check-result');
    expect(store.value.pendingCommand, isNull); expect(client.invoices, 0); expect(client.sent, hasLength(1));
    await billTap(tester, 'bill-checkout'); await billTap(tester, 'bill-confirm-checkout');
    expect(client.sent.last.operation, LanWriteOperation.sessionCheckout); expect(client.invoices, 1);
    await tester.pumpWidget(const SizedBox()); commands.dispose();
  });

  testWidgets('uncommitted lost checkout retries the same durable command only after checking desktop', (tester) async {
    final client = BillTestClient(), store = BillTestStore(); final commands = await mountBill(tester, client, store: store);
    await billTap(tester, 'bill-checkout'); client.unavailable = true; await billTap(tester, 'bill-confirm-checkout');
    expect(client.invoices, 0); expect(client.sent, hasLength(1));
    final original = store.value.pendingCommand!;
    expect(find.byKey(const Key('write-retry-command')), findsNothing);
    client.unavailable = false; await billTap(tester, 'write-check-result');
    expect(commands.canRetry, isTrue); await billTap(tester, 'write-retry-command');
    expect(client.sent, hasLength(2)); expect(client.sent.last.commandId, original.commandId);
    expect(client.sent.last.signature, original.signature); expect(client.invoices, 1);
    expect(find.text('Thanh toán thành công'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); commands.dispose();
  });

  testWidgets('background and revoke remove nested bill editors, pickers and checkout dialogs', (tester) async {
    final store = BillTestStore(), client = BillTestClient(), pairing = _BillPairing();
    await tester.pumpWidget(MaterialApp(theme: companionTheme(), home: Scaffold(body:
      CompanionAccessPanel(connection: billConnection, client: pairing, store: store, readClient: client,
        workflowClient: client, onAccess: (_) {}))));
    await tester.pumpAndSettle(); await billTap(tester, 'mobile-tab-invoices');
    await billTap(tester, 'bill-list-bill-a'); await billTap(tester, 'bill-edit-line-service'); await billTap(tester, 'bill-line-employee');
    expect(find.byType(CompanionCatalogPicker), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused); await tester.pumpAndSettle();
    expect(find.byType(CompanionMobileBill), findsNothing); expect(find.byType(CompanionBillLineEditor), findsNothing);
    expect(find.byType(CompanionCatalogPicker), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed); await tester.pumpAndSettle();
    await billTap(tester, 'mobile-tab-invoices'); await billTap(tester, 'bill-list-bill-a'); await billTap(tester, 'bill-checkout');
    expect(find.byType(AlertDialog), findsOneWidget);
    pairing.state = PhoneAccess.revoked; await tester.pump(const Duration(seconds: 5)); await tester.pumpAndSettle();
    expect(find.byType(CompanionMobileBill), findsNothing); expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CompanionWorkspace), findsNothing); expect(client.sent, isEmpty);
    expect(tester.takeException(), isNull); await tester.pumpWidget(const SizedBox());
  });

}
