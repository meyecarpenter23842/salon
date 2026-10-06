import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salonmanager/core/lan/lan_connection_qr.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_pairing_client.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/features/companion/companion_app.dart';
import 'package:salonmanager/features/companion/companion_credential_store.dart';
import 'support/mobile_bill_fixture.dart';
import 'companion_mobile_bill_test.dart' show billTap;
class _Checker implements LanHealthChecker {
  final checked = <LanConnection>[];
  @override Future<void> check(LanConnection connection) async { checked.add(connection); }
}
class _Pending implements LanPairingClient {
  PairedPhone get phone => PairedPhone('a' * 64, 'Phone', PhoneAccess.pending, DateTime.utc(2026));
  @override Future<PairedPhone> status(LanConnection c, String token) async => phone;
  @override Future<PairedPhone> bootstrap(LanConnection c, String token) async => phone;
  @override Future<PairedPhone> request(LanConnection c, String code, String name, String token) async => phone;
}
void main() {
  testWidgets('scanner invalid/cancel/accept never bypass pinned check or owner approval', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final checker = _Checker(), store = BillTestStore(), client = BillTestClient();
    final connection = LanConnection('https://192.168.1.20:8743/api/staff/v1', 'b' * 64);
    final raw = LanConnectionQr.encode(connection);
    ValueChanged<String>? detect;
    await tester.pumpWidget(SalonCompanionApp(checker: checker, pairingClient: _Pending(), credentialStore: store,
      readClient: client, workflowClient: client, scannerPreview: (context, callback) {
        detect = callback; return const Center(child: Text('Camera preview'));
      }));
    await tester.pumpAndSettle(); await billTap(tester, 'companion-scan-qr');
    detect!('invalid'); await tester.pumpAndSettle();
    expect(find.byKey(const Key('qr-scan-error')), findsOneWidget);
    detect!(raw); detect!(raw); await tester.pumpAndSettle();
    expect(find.text('Xác nhận máy salon'), findsOneWidget);
    expect(checker.checked, isEmpty); expect(client.searches, isEmpty);
    await tester.tap(find.text('Hủy')); await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const Key('companion-url'))).controller!.text, '');
    await billTap(tester, 'companion-scan-qr'); detect!(raw); await tester.pumpAndSettle();
    await billTap(tester, 'companion-qr-accept');
    expect(tester.widget<TextFormField>(find.byKey(const Key('companion-url'))).controller!.text, connection.apiUrl.toString());
    expect(tester.widget<TextFormField>(find.byKey(const Key('companion-pin'))).controller!.text, 'b' * 64);
    expect(checker.checked, isEmpty);
    expect((await SharedPreferences.getInstance()).getString('companion_api_url'), isNull);
    await billTap(tester, 'companion-check'); expect(checker.checked.single.apiUrl, connection.apiUrl);
    expect(checker.checked.single.certificateSha256, 'b' * 64);
    expect((await SharedPreferences.getInstance()).getString('companion_api_url'), connection.apiUrl.toString());
    expect(client.searches, isEmpty); expect(client.sent, isEmpty);
    expect(tester.takeException(), isNull); await tester.pumpWidget(const SizedBox());
  });
  testWidgets('paste rejects malformed QR; uncertain command prevents changing salon identity', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = BillTestStore(), checker = _Checker(), client = BillTestClient();
    store.value = CompanionCredential('b' * 64, 'c' * 64, pendingCommand:
      LanWriteCommand(commandId: 'pending-qr', operation: LanWriteOperation.sessionCheckout,
        targetId: 'bill-a', expectedEpoch: 'epoch-a', expectedRevision: 1, payload: {}));
    await tester.pumpWidget(SalonCompanionApp(checker: checker, pairingClient: _Pending(), credentialStore: store,
      readClient: client, workflowClient: client));
    await tester.pumpAndSettle();
    Future<void> paste(String text) async {
      await billTap(tester, 'companion-paste-qr');
      await tester.enterText(find.byKey(const Key('companion-qr-text')), text);
      await billTap(tester, 'companion-qr-import');
    }
    await paste('{}'); expect(find.textContaining('Thông tin QR không hợp lệ'), findsOneWidget);
    await paste(LanConnectionQr.encode(LanConnection('https://192.168.1.21:8743/api/staff/v1', 'a' * 64)));
    expect(find.textContaining('Có yêu cầu chưa rõ kết quả'), findsOneWidget);
    expect(find.byKey(const Key('companion-qr-accept')), findsNothing);
    expect(store.value.pendingCommand!.commandId, 'pending-qr'); expect(checker.checked, isEmpty);
    await paste(LanConnectionQr.encode(LanConnection('https://192.168.1.21:8743/api/staff/v1', 'b' * 64)));
    await billTap(tester, 'companion-qr-accept');
    expect(tester.widget<TextFormField>(find.byKey(const Key('companion-url'))).controller!.text,
      'https://192.168.1.21:8743/api/staff/v1');
    expect(store.value.pendingCommand!.commandId, 'pending-qr');
    expect(tester.takeException(), isNull); await tester.pumpWidget(const SizedBox());
  });
  testWidgets('manual settings cannot replace pin while an uncertain command is saved', (tester) async {
    SharedPreferences.setMockInitialValues({
      'companion_api_url': 'https://192.168.1.20:8743/api/staff/v1',
      'companion_certificate_sha256': 'b' * 64,
    });
    final store = BillTestStore(), checker = _Checker(), client = BillTestClient();
    store.value = CompanionCredential('b' * 64, 'c' * 64, pendingCommand:
      LanWriteCommand(commandId: 'pending-manual', operation: LanWriteOperation.sessionCheckout,
        targetId: 'bill-a', expectedEpoch: 'epoch-a', expectedRevision: 1, payload: {}));
    await tester.pumpWidget(SalonCompanionApp(checker: checker, pairingClient: _Pending(),
      credentialStore: store, readClient: client, workflowClient: client));
    await tester.pumpAndSettle();
    await billTap(tester, 'companion-connection-settings');
    await tester.enterText(find.byKey(const Key('companion-pin')), 'a' * 64);
    await billTap(tester, 'companion-check');
    expect(find.textContaining('Có yêu cầu chưa rõ kết quả'), findsOneWidget);
    expect(checker.checked, isEmpty);
    expect(store.value.token, 'c' * 64);
    expect(store.value.pendingCommand!.commandId, 'pending-manual');
    expect((await SharedPreferences.getInstance()).getString('companion_certificate_sha256'), 'b' * 64);
    await tester.pumpWidget(const SizedBox());
  });

}
