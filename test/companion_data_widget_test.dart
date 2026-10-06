import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_contract.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_pairing_client.dart';
import 'package:salonmanager/core/lan/lan_read_client.dart';
import 'package:salonmanager/core/lan/lan_read_models.dart';
import 'package:salonmanager/features/companion/companion_access_panel.dart';
import 'package:salonmanager/features/companion/companion_credential_store.dart';
import 'package:salonmanager/features/companion/companion_data_panel.dart';
import 'package:salonmanager/features/companion/companion_workspace.dart';

class _ReadClient implements SalonReadClient {
  final queries = <SalonReadQuery>[];
  bool denied = false;
  Completer<SalonReadPage>? delayed;
  @override
  Future<SalonReadPage> read(LanConnection connection, String token, SalonReadQuery query) async {
    queries.add(query);
    if (denied) throw const PairingFailure(LanErrorCode.forbidden);
    if (delayed != null) return delayed!.future;
    return SalonReadPage(salonDate: '2026-10-05', nextOffset: query.offset == 0 && query.id == null ? 25 : null,
      records: [SalonReadRecord(id: 'record-${query.kind.name}',
        title: 'Dữ liệu ${query.kind.name}', subtitle: 'Từ desktop',
        fields: query.id == null ? const {} : {'Ghi chú': 'Chi tiết thật'})]);
  }
}

class _PairClient implements LanPairingClient {
  PhoneAccess state = PhoneAccess.approved;
  bool readAccess = true;
  bool offline = false;
  PairedPhone get phone => PairedPhone('a' * 64, 'Phone', state, DateTime.utc(2026),
    canReadSalon: readAccess);
  @override
  Future<PairedPhone> status(LanConnection connection, String token) async {
    if (offline) throw const PairingFailure(LanErrorCode.unavailable);
    return phone;
  }
  @override
  Future<PairedPhone> bootstrap(LanConnection connection, String token) => status(connection, token);
  @override
  Future<PairedPhone> request(LanConnection connection, String code, String name, String token) =>
      status(connection, token);
}

class _Store implements CompanionCredentialStore {
  @override
  Future<CompanionCredential?> read() async => CompanionCredential('b' * 64, 'c' * 64);
  @override
  Future<void> write(CompanionCredential value) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  final connection = LanConnection('https://192.168.1.20:8743/api/staff/v1', 'b' * 64);
  Future<void> showPanel(WidgetTester tester, _ReadClient client) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: CompanionDataPanel(connection: connection, token: 'c' * 64,
        client: client, onDenied: () {})))));
    await tester.pumpAndSettle();
  }
  Future<void> tap(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    await tester.ensureVisible(finder); await tester.pump();
    await tester.tap(finder); await tester.pumpAndSettle();
  }

  testWidgets('narrow phone shows three read sections, customer search, detail and bounded paging', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = _ReadClient();
    await showPanel(tester, client);
    await tester.enterText(find.byKey(const Key('salon-customer-search')), '090123');
    await tap(tester, const Key('salon-search'));
    expect(client.queries.last.query, '090123');
    await tap(tester, const Key('salon-next-page'));
    expect(client.queries.last.offset, 25);
    await tap(tester, const Key('salon-record-record-customers'));
    expect(find.text('Ghi chú: Chi tiết thật'), findsOneWidget);
    await tap(tester, const Key('salon-detail-back'));
    await tap(tester, const Key('salon-tab-invoices'));
    expect(client.queries.last.kind, SalonReadKind.invoices);
    await tap(tester, const Key('salon-tab-appointments'));
    expect(client.queries.last.kind, SalonReadKind.appointments);
    expect(find.text('Ngày trên máy salon: 2026-10-05'), findsOneWidget);
    await tap(tester, const Key('salon-pick-day'));
    await tester.tap(find.text('6').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(client.queries.last.day, '2026-10-06');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('changing sections rejects stale reads; denied response clears private data', (tester) async {
    final client = _ReadClient();
    await showPanel(tester, client);
    client.delayed = Completer<SalonReadPage>();
    await tester.tap(find.byKey(const Key('salon-data-refresh')));
    await tester.pump();
    final pending = client.delayed!;
    client.delayed = null;
    await tap(tester, const Key('salon-tab-invoices'));
    pending.complete(const SalonReadPage(salonDate: '2026-10-05', records: [
      SalonReadRecord(id: 'old', title: 'Stale private data', subtitle: ''),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Stale private data'), findsNothing);
    expect(find.text('Dữ liệu invoices'), findsOneWidget);
    client.denied = true;
    await tap(tester, const Key('salon-data-refresh'));
    expect(find.text('Dữ liệu invoices'), findsNothing);
    expect(find.byKey(const Key('salon-read-error')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('foreground, connection and owner permission gate all cached mobile data', (tester) async {
    final reader = _ReadClient();
    final pair = _PairClient();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      CompanionAccessPanel(connection: connection, client: pair,
        store: _Store(), readClient: reader, onAccess: (_) {}))));
    await tester.pumpAndSettle();
    expect(find.text('Dữ liệu appointments'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(find.text('Dữ liệu appointments'), findsNothing);
    pair.readAccess = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(CompanionWorkspace), findsNothing);
    pair.readAccess = true;
    await tester.pump(const Duration(seconds: 5)); await tester.pumpAndSettle();
    expect(find.text('Dữ liệu appointments'), findsOneWidget);
    pair.offline = true;
    await tester.pump(const Duration(seconds: 5)); await tester.pumpAndSettle();
    expect(find.text('Dữ liệu appointments'), findsNothing);
    pair.offline = false; pair.state = PhoneAccess.revoked;
    await tester.pump(const Duration(seconds: 5)); await tester.pumpAndSettle();
    expect(find.byType(CompanionWorkspace), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
