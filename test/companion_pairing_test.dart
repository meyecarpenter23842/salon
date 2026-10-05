import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salonmanager/core/lan/desktop_lan_controller.dart';
import 'package:salonmanager/core/lan/desktop_pairing_panel.dart';
import 'package:salonmanager/core/lan/lan_contract.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_pairing_client.dart';
import 'package:salonmanager/core/providers/data_backend_provider.dart';
import 'package:salonmanager/features/companion/companion_app.dart';
import 'package:salonmanager/features/companion/companion_credential_store.dart';

class _Health implements LanHealthChecker {
  @override
  Future<void> check(LanConnection connection) async {}
}

class _Store implements CompanionCredentialStore {
  CompanionCredential? value;
  bool fail = false;
  @override
  Future<CompanionCredential?> read() async => value;
  @override
  Future<void> write(CompanionCredential credential) async {
    if (fail) throw StateError('private store');
    value = credential;
  }
  @override
  Future<void> clear() async => value = null;
}

class _Client implements LanPairingClient {
  PhoneAccess state = PhoneAccess.pending;
  int requests = 0;
  bool offline = false;
  Completer<void>? delayed;
  PairedPhone get phone => PairedPhone('a' * 64, 'Phone A', state, DateTime.utc(2026));
  @override
  Future<PairedPhone> request(LanConnection connection, String code, String name, String token) async {
    requests++;
    if (delayed != null) await delayed!.future;
    return phone;
  }
  @override
  Future<PairedPhone> status(LanConnection connection, String token) async {
    if (offline) throw const PairingFailure(LanErrorCode.unavailable);
    return phone;
  }
  @override
  Future<PairedPhone> bootstrap(LanConnection connection, String token) async {
    if (state != PhoneAccess.approved) throw const PairingFailure(LanErrorCode.forbidden);
    return phone;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
    'companion_api_url': 'https://192.168.1.20:8743/api/staff/v1',
    'companion_certificate_sha256': 'b' * 64,
  }));

  Future<void> showApp(WidgetTester tester, _Client client, _Store store) async {
    await tester.pumpWidget(SalonCompanionApp(
      checker: _Health(), pairingClient: client, credentialStore: store));
    await tester.pumpAndSettle();
  }

  Future<void> request(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('companion-pair-code')));
    await tester.enterText(find.byKey(const Key('companion-pair-code')), '12345678');
    await tester.ensureVisible(find.byKey(const Key('companion-request')));
    await tester.tap(find.byKey(const Key('companion-request')));
    await tester.pumpAndSettle();
  }

  testWidgets('wait for approval, enter home, show offline, detect revoke and restore safe shell', (tester) async {
    final client = _Client();
    final store = _Store();
    await showApp(tester, client, store);
    await request(tester);
    expect(find.text('Salon — Trang chính'), findsNothing);
    expect(find.textContaining('Đang chờ chủ salon'), findsOneWidget);
    expect(store.value!.pin, 'b' * 64);
    client.state = PhoneAccess.approved;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Salon — Trang chính'), findsOneWidget);
    expect(find.text('Đang kết nối với máy salon'), findsOneWidget);
    expect(find.byKey(const Key('companion-url')), findsNothing);
    client.offline = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mất kết nối'), findsOneWidget);
    client.offline = false;
    client.state = PhoneAccess.revoked;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Salon — Trang chính'), findsNothing);
    expect(find.textContaining('đã bị thu hồi'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('approved credential restores home after app restart; token stays bound to pin', (tester) async {
    final client = _Client()..state = PhoneAccess.approved;
    final store = _Store()..value = CompanionCredential('b' * 64, 'c' * 64);
    await showApp(tester, client, store);
    expect(find.text('Salon — Trang chính'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.value = CompanionCredential('d' * 64, 'c' * 64);
    await showApp(tester, client, store);
    expect(find.text('Salon — Trang chính'), findsNothing);
    expect(client.requests, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed secure save sends no request and does not grant access', (tester) async {
    final client = _Client();
    final store = _Store()..fail = true;
    await showApp(tester, client, store);
    await request(tester);
    expect(client.requests, 0);
    expect(find.textContaining('Chưa gửi được'), findsOneWidget);
    expect(find.textContaining('private store'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('background ignores late approval; resume revalidates before home', (tester) async {
    final client = _Client()..delayed = Completer<void>();
    final store = _Store();
    await showApp(tester, client, store);
    await tester.enterText(find.byKey(const Key('companion-pair-code')), '12345678');
    await tester.ensureVisible(find.byKey(const Key('companion-request')));
    await tester.tap(find.byKey(const Key('companion-request')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    client.state = PhoneAccess.approved;
    client.delayed!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Salon — Trang chính'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Salon — Trang chính'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop displays requests and revokes each phone independently', (tester) async {
    final root = (await tester.runAsync(() => Directory.systemTemp.createTemp('salon-pair-panel-')))!;
    final registry = LanPairingRegistry(file: File('${root.path}/devices.json'));
    registry.setActive(true);
    final a = (await tester.runAsync(() async => registry.request(await registry.createCode(), 'Phone A', newDeviceSecret())))!;
    final b = (await tester.runAsync(() async => registry.request(await registry.createCode(), 'Phone B', newDeviceSecret())))!;
    final old = desktopPhoneRegistry.value;
    desktopPhoneRegistry.value = registry;
    try {
      await tester.pumpWidget(ProviderScope(
        overrides: [appDataBackendProvider.overrideWithValue(AppDataBackend.fake)],
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DesktopPairingPanel())))));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(Key('phone-approve-${a.id}')));
        await registry.settled;
      });
      await tester.pumpAndSettle();
      expect(registry.phones.first.state, PhoneAccess.approved);
      expect(registry.phones.last.state, PhoneAccess.pending);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(Key('phone-revoke-${a.id}')));
        await registry.settled;
      });
      await tester.pumpAndSettle();
      expect(registry.phones.first.state, PhoneAccess.revoked);
      expect(registry.phones.last.id, b.id);
      await tester.pumpWidget(const SizedBox());
    } finally {
      desktopPhoneRegistry.value = old;
      registry.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    }
  });
}
