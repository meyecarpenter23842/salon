import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_changes.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_contract.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_pairing_client.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/features/companion/companion_access_panel.dart';
import 'package:salonmanager/features/companion/companion_bill_editors.dart';
import 'package:salonmanager/features/companion/companion_command_controller.dart';
import 'package:salonmanager/features/companion/companion_workspace.dart';
import 'support/mobile_bill_fixture.dart';
import 'companion_mobile_bill_test.dart' show billConnection, billTap, mountBill;

class _Pair implements LanPairingClient {
  bool offline = false;
  PhoneAccess access = PhoneAccess.approved;
  PairedPhone get phone => PairedPhone('a' * 64, 'Phone', access, DateTime.utc(2026),
    canReadSalon: access == PhoneAccess.approved, writeRole: PhoneWriteRole.cashier);
  @override Future<PairedPhone> status(LanConnection c, String token) async {
    if (offline) throw const PairingFailure(LanErrorCode.unavailable);
    return phone;
  }
  @override Future<PairedPhone> bootstrap(LanConnection c, String token) async => status(c, token);
  @override Future<PairedPhone> request(LanConnection c, String code, String name, String token) async => status(c, token);
}
class _Changes implements LanChangeClient {
  String epoch = 'epoch-a';
  int cursor = 1;
  Completer<LanChangeSnapshot>? delayed;
  @override Future<LanChangeSnapshot> read(LanConnection c, String token, String? previous, int after) async =>
    delayed == null ? LanChangeSnapshot(epoch, cursor, reset: previous != epoch, changed: previous != epoch || after != cursor) : delayed!.future;
}
void main() {
  testWidgets('offline keeps nested unsaved line, locks writes; reconnect invalidates snapshot and revoke clears routes', (tester) async {
    final pair = _Pair(), changes = _Changes(), store = BillTestStore(), client = BillTestClient();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CompanionAccessPanel(
      connection: billConnection, client: pair, store: store, readClient: client,
      workflowClient: client, changeClient: changes, onAccess: (_) {}))));
    await tester.pumpAndSettle(); await billTap(tester, 'mobile-tab-invoices');
    await billTap(tester, 'bill-list-bill-a'); await billTap(tester, 'bill-edit-line-service');
    await tester.enterText(find.byKey(const Key('bill-line-quantity')), '3');
    pair.offline = true;
    await tester.pump(const Duration(seconds: 5)); await tester.pumpAndSettle();
    expect(find.byType(CompanionBillLineEditor), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byKey(const Key('bill-line-quantity'))).controller!.text, '3');
    expect(tester.widget<FilledButton>(find.byKey(const Key('bill-line-save'))).onPressed, isNull);
    expect(find.byKey(const Key('mobile-reconnect')), findsOneWidget); expect(client.sent, isEmpty);
    pair.offline = false; changes.cursor = 8;
    await billTap(tester, 'mobile-reconnect');
    expect(tester.widget<TextFormField>(find.byKey(const Key('bill-line-quantity'))).controller!.text, '3');
    expect(tester.widget<FilledButton>(find.byKey(const Key('bill-line-save'))).onPressed, isNull);
    expect(find.textContaining('Dữ liệu có thể đã đổi'), findsOneWidget);
    pair.access = PhoneAccess.revoked;
    await tester.pump(const Duration(seconds: 5)); await tester.pumpAndSettle();
    expect(find.byType(CompanionBillLineEditor), findsNothing); expect(find.byType(CompanionWorkspace), findsNothing);
    expect(client.sent, isEmpty); expect(tester.takeException(), isNull); await tester.pumpWidget(const SizedBox());
  });

  testWidgets('change notification reloads active bills without losing query; duplicate cursors do not read again', (tester) async {
    final client = BillTestClient(), commands = await mountBill(tester, client, workspace: true);
    commands.applyChanges(const LanChangeSnapshot('epoch-a', 1, reset: true, changed: true)); await tester.pumpAndSettle();
    await billTap(tester, 'mobile-tab-invoices');
    await tester.enterText(find.byKey(const Key('bill-list-search-0')), 'bill-');
    await billTap(tester, 'bill-list-find');
    client.sessions['bill-a']!['customerLabel'] = 'Đã sửa trên desktop';
    commands.applyChanges(const LanChangeSnapshot('epoch-a', 5, reset: false, changed: true));
    await tester.pumpAndSettle();
    expect(find.text('Đã sửa trên desktop'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('bill-list-search-0'))).controller!.text, 'bill-');
    final count = client.searches.length, generation = commands.dataGeneration;
    commands.applyChanges(const LanChangeSnapshot('epoch-a', 5, reset: false, changed: true));
    commands.applyChanges(const LanChangeSnapshot('epoch-a', 2, reset: false, changed: true));
    await tester.pumpAndSettle(); expect(client.searches.length, count); expect(commands.dataGeneration, generation);
    commands.applyChanges(const LanChangeSnapshot('epoch-new', 1, reset: true, changed: true));
    await tester.pumpAndSettle(); expect(client.searches.length, greaterThan(count));
    await tester.pumpWidget(const SizedBox()); commands.dispose();
  });

  test('reconnect and new epoch do not resend an uncertain checkout; checks remain explicit', () async {
    final client = BillTestClient()..loseCheckout = true, store = BillTestStore();
    final commands = CompanionCommandController(connection: billConnection, client: client,
      store: store, credential: store.value, onCredential: (_) {});
    try {
      final snapshot = await client.editor(billConnection, commands.token, 'session', 'bill-a');
      await commands.submit(LanWriteOperation.sessionCheckout, snapshot, {});
      final id = commands.pending!.commandId;
      commands.connectionState(connected: false);
      await commands.check(); await commands.retry(); expect(client.sent, hasLength(1));
      commands.applyChanges(const LanChangeSnapshot('restarted-desktop', 1, reset: true, changed: true), reconnect: true);
      expect(commands.pending!.commandId, id); expect(client.sent, hasLength(1)); expect(client.invoices, 1);
      await commands.check();
      expect(commands.pending, isNull); expect(commands.lastResult!.id, 'invoice-1'); expect(client.sent, hasLength(1));
    } finally { commands.dispose(); }
  });
}
