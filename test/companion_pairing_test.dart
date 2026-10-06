import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/services/sensitive_action_service.dart';
import 'package:salonmanager/core/providers/repository_providers.dart';
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
  bool failRead = false;
  @override
  Future<CompanionCredential?> read() async {
    if (failRead) throw StateError('secure storage locked');
    return value;
  }
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
  Completer<void>? statusDelay;
  final statusTokens = <String>[];
  int activeStatuses = 0;
  int maxStatuses = 0;
  PairedPhone get phone => PairedPhone('a' * 64, 'Phone A', state, DateTime.utc(2026));
  @override
  Future<PairedPhone> request(LanConnection connection, String code, String name, String token) async {
    requests++;
    if (delayed != null) await delayed!.future;
    return phone;
  }
  @override
  Future<PairedPhone> status(LanConnection connection, String token) async {
    statusTokens.add(token);
    activeStatuses++;
    if (activeStatuses > maxStatuses) maxStatuses = activeStatuses;
    try {
      if (statusDelay != null) await statusDelay!.future;
      if (offline) throw const PairingFailure(LanErrorCode.unavailable);
      return phone;
    } finally { activeStatuses--; }
  }
  @override
  Future<PairedPhone> bootstrap(LanConnection connection, String token) async {
    if (state != PhoneAccess.approved) throw const PairingFailure(LanErrorCode.forbidden);
    return phone;
  }
}

class _PanelRegistry extends LanPairingRegistry {
  _PanelRegistry() : super(file: File('unused-test-device-store'));
  final entries = [
    PairedPhone('a' * 64, 'Phone A', PhoneAccess.pending, DateTime.utc(2026)),
    PairedPhone('b' * 64, 'Phone B', PhoneAccess.pending, DateTime.utc(2026)),
  ];
  @override
  bool get active => true;
  @override
  List<PairedPhone> get phones => List.unmodifiable(entries);
  @override
  Future<void> decide(String id, PhoneAccess state) async {
    final index = entries.indexWhere((p) => p.id == id);
    entries[index] = entries[index].withState(state);
    notifyListeners();
  }
}

class _LockedSecurity extends SensitiveActionService {
  _LockedSecurity() : super(SalonDatabase.instance);
  @override
  bool get isOwnerSessionActive => false;
  @override
  Future<bool> isProtectionConfigured() async => true;
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
    await tester.pump();
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
    await request(tester);
    expect(client.requests, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    client.state = PhoneAccess.approved;
    client.delayed!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Salon — Trang chính'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Salon — Trang chính'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop displays requests and revokes each phone independently', (tester) async {
    final registry = _PanelRegistry();
    final a = registry.phones.first;
    final b = registry.phones.last;
    final old = desktopPhoneRegistry.value;
    desktopPhoneRegistry.value = registry;
    try {
      await tester.pumpWidget(ProviderScope(
        overrides: [appDataBackendProvider.overrideWithValue(AppDataBackend.fake)],
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DesktopPairingPanel())))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('phone-approve-${a.id}')));
      await tester.pumpAndSettle();
      expect(registry.phones.first.state, PhoneAccess.approved);
      expect(registry.phones.last.state, PhoneAccess.pending);
      await tester.tap(find.byKey(Key('phone-revoke-${a.id}')));
      await tester.pumpAndSettle();
      expect(registry.phones.first.state, PhoneAccess.revoked);
      expect(registry.phones.last.id, b.id);
      await tester.pumpWidget(const SizedBox());
    } finally {
      desktopPhoneRegistry.value = old;
      registry.dispose();
    }
  });
  testWidgets('locked desktop Owner must authorize before a phone can be approved', (tester) async {
    final registry = _PanelRegistry();
    final old = desktopPhoneRegistry.value;
    desktopPhoneRegistry.value = registry;
    try {
      await tester.pumpWidget(ProviderScope(
        overrides: [sensitiveActionServiceProvider.overrideWithValue(_LockedSecurity())],
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DesktopPairingPanel())))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('phone-approve-${'a' * 64}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('owner-authorization-dialog')), findsOneWidget);
      expect(registry.phones.first.state, PhoneAccess.pending);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(registry.phones.first.state, PhoneAccess.pending);
      await tester.pumpWidget(const SizedBox());
    } finally {
      desktopPhoneRegistry.value = old;
      registry.dispose();
    }
  });

  testWidgets('saved identity survives offline restart; automatic probes stay quiet and do not pair again', (tester) async {
    final client = _Client()..offline = true;
    final store = _Store()..value = CompanionCredential('b' * 64, 'c' * 64);
    await showApp(tester, client, store);
    expect(find.byKey(const Key('companion-url')), findsNothing);
    expect(find.byKey(const Key('companion-pair-code')), findsNothing);
    expect(find.textContaining('Mất kết nối'), findsOneWidget);
    client.statusDelay = Completer<void>();
    await tester.pump(const Duration(seconds: 5)); await tester.pump();
    expect(find.text('Đang kiểm tra…'), findsNothing);
    expect(find.byKey(const Key('companion-pair-code')), findsNothing);
    await tester.pump(const Duration(seconds: 15));
    expect(client.maxStatuses, 1);
    client.offline = false; client.state = PhoneAccess.approved;
    client.statusDelay!.complete(); client.statusDelay = null;
    await tester.pumpAndSettle();
    expect(find.text('Salon — Trang chính'), findsOneWidget);
    expect(client.requests, 0); expect(client.statusTokens.toSet(), {'c' * 64});
    expect(store.value!.token, 'c' * 64);
    await tester.pumpWidget(const SizedBox());
    await showApp(tester, client, store);
    expect(find.byKey(const Key('companion-pair-code')), findsNothing);
    expect(client.requests, 0); await tester.pumpWidget(const SizedBox());
  });

  testWidgets('editing connection is deliberate; cancel and same-pin IP change retain device identity', (tester) async {
    final client = _Client()..state = PhoneAccess.approved;
    final store = _Store()..value = CompanionCredential('b' * 64, 'c' * 64);
    await showApp(tester, client, store);
    await tester.tap(find.byKey(const Key('companion-connection-settings')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(find.byKey(const Key('companion-pin'))).controller!.text, 'b' * 64);
    await tester.enterText(find.byKey(const Key('companion-url')), 'https://192.168.1.21:8743/api/staff/v1');
    await tester.tap(find.byKey(const Key('companion-settings-back'))); await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getString('companion_api_url'), contains('192.168.1.20'));
    expect(find.byKey(const Key('companion-url')), findsNothing);
    await tester.tap(find.byKey(const Key('companion-connection-settings')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('companion-url')), 'https://192.168.1.21:8743/api/staff/v1');
    await tester.ensureVisible(find.byKey(const Key('companion-check')));
    await tester.tap(find.byKey(const Key('companion-check'))); await tester.pumpAndSettle();
    expect(find.byKey(const Key('companion-url')), findsNothing);
    expect((await SharedPreferences.getInstance()).getString('companion_api_url'), contains('192.168.1.21'));
    expect(client.requests, 0); expect(store.value!.token, 'c' * 64);
    expect(client.statusTokens.toSet(), {'c' * 64});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unreadable secure storage never presents a fresh pairing form; retry restores saved identity', (tester) async {
    final client = _Client()..state = PhoneAccess.approved;
    final store = _Store()..value = CompanionCredential('b' * 64, 'c' * 64)..failRead = true;
    await showApp(tester, client, store);
    expect(find.byKey(const Key('companion-pair-code')), findsNothing);
    expect(find.textContaining('không cần lấy mã ghép mới'), findsOneWidget);
    store.failRead = false;
    await tester.tap(find.byKey(const Key('companion-storage-retry')));
    await tester.pumpAndSettle();
    expect(find.text('Salon — Trang chính'), findsOneWidget);
    expect(client.requests, 0); await tester.pumpWidget(const SizedBox());
  });

  testWidgets('confirmed revoke exposes pairing once; fresh approval uses a new identity', (tester) async {
    final client = _Client()..state = PhoneAccess.approved;
    final store = _Store()..value = CompanionCredential('b' * 64, 'c' * 64);
    await showApp(tester, client, store);
    client.state = PhoneAccess.revoked;
    await tester.pump(const Duration(seconds: 5)); await tester.pumpAndSettle();
    expect(find.byKey(const Key('companion-pair-code')), findsOneWidget);
    final count = client.statusTokens.length;
    await tester.pump(const Duration(seconds: 15)); await tester.pumpAndSettle();
    expect(client.statusTokens.length, count);
    client.state = PhoneAccess.pending;
    await request(tester);
    expect(client.requests, 1);
    expect(store.value!.token, isNot('c' * 64));
    expect(find.byKey(const Key('companion-pair-code')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

}
