import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_contract.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
import 'package:salonmanager/core/lan/lan_pairing.dart';
import 'package:salonmanager/core/lan/lan_workflow_client.dart';
import 'package:salonmanager/core/lan/lan_workflow_models.dart';
import 'package:salonmanager/core/lan/lan_write_contract.dart';
import 'package:salonmanager/features/companion/companion_command_controller.dart';
import 'package:salonmanager/features/companion/companion_credential_store.dart';

class _Store implements CompanionCredentialStore {
  CompanionCredential? value = CompanionCredential('b' * 64, 'c' * 64);
  bool failWrite = false;
  bool failClearPending = false;
  @override Future<CompanionCredential?> read() async => value;
  @override Future<void> clear() async { value = null; }
  @override Future<void> write(CompanionCredential credential) async {
    if (failWrite || failClearPending && credential.pendingCommand == null) throw StateError('Storage');
    value = credential;
  }
}
class _Client implements LanWorkflowClient {
  _Client(this.store);
  final _Store store;
  final sent = <LanWriteCommand>[];
  Object? error;
  String epoch = 'epoch-1';
  LanWriteResult? saved;
  @override Future<LanWriteResult> send(LanConnection c, String token, LanWriteCommand command) async {
    expect(store.value?.pendingCommand?.signature, command.signature);
    sent.add(command);
    if (error != null) throw error!;
    return saved ?? const LanWriteResult(id: 'customer-1', type: 'customer', revision: 1);
  }
  @override Future<LanWriteResult?> result(LanConnection c, String token, String id) async => saved;
  @override Future<LanEditorSnapshot> editor(LanConnection c, String token, String kind, String? id) async =>
    LanEditorSnapshot(kind: kind, epoch: epoch, id: id, revision: 0, values: const {});
  @override Future<LanCatalogPage> catalog(LanConnection c, String token, String kind, String q, int offset) async =>
    LanCatalogPage(const [], epoch, null);
}
const snapshot = LanEditorSnapshot(kind: 'customer', epoch: 'epoch-1', revision: 0, values: {});

void main() {
  final connection = LanConnection('https://192.168.1.20:8743/api/staff/v1', 'b' * 64);
  CompanionCommandController controller(_Store s, _Client c) => CompanionCommandController(
    connection: connection, client: c, store: s, credential: s.value!, onCredential: (_) {});
  test('persist before send; storage failure never sends and keeps conservative pending lock', () async {
    final store = _Store()..failWrite = true;
    final client = _Client(store);
    final c = controller(store, client);
    expect(await c.submit(LanWriteOperation.customerCreate, snapshot, {}), isNull);
    expect(client.sent, isEmpty); expect(c.blocked, isTrue);
    c.dispose();
  });
  test('timeout survives recreation, blocks new command and manual result resolves without resending', () async {
    final store = _Store(); final client = _Client(store)..error = TimeoutException('No response');
    var c = controller(store, client);
    await c.submit(LanWriteOperation.customerCreate, snapshot, {});
    final id = c.pending!.commandId;
    await c.submit(LanWriteOperation.customerCreate, snapshot, {});
    expect(client.sent, hasLength(1));
    c.dispose(); c = controller(store, client);
    expect(c.pending!.commandId, id);
    client.saved = const LanWriteResult(id: 'customer-1', type: 'customer', revision: 1);
    await c.check();
    expect(c.blocked, isFalse); expect(store.value!.pendingCommand, isNull);
    expect(client.sent, hasLength(1)); expect(c.lastResult!.id, 'customer-1'); c.dispose();
  });
  test('manual retry preserves exact command, revoked retry stays unresolved and failed durable clear blocks', () async {
    final store = _Store(); final client = _Client(store)..error = TimeoutException('Lost');
    final c = controller(store, client);
    await c.submit(LanWriteOperation.customerCreate, snapshot, {'fullName': 'Private'});
    final signature = c.pending!.signature;
    await c.check(); expect(c.canRetry, isTrue);
    client.error = const PairingFailure(LanErrorCode.forbidden);
    await c.retry();
    expect(c.pending!.signature, signature); expect(c.blocked, isTrue);
    client.saved = const LanWriteResult(id: 'customer-1', type: 'customer', revision: 1);
    store.failClearPending = true;
    await c.check(); expect(c.blocked, isTrue);
    store.failClearPending = false; await c.check(); expect(c.blocked, isFalse);
    expect(client.sent.every((command) => command.signature == signature), isTrue); c.dispose();
  });
  test('missing result after changed desktop epoch permits explicit discard but never automatic replay', () async {
    final store = _Store(); final client = _Client(store)..error = TimeoutException('Lost');
    final c = controller(store, client);
    await c.submit(LanWriteOperation.customerCreate, snapshot, {});
    client.epoch = 'epoch-2';
    await c.check(); expect(c.oldEpoch, isTrue); expect(c.canRetry, isFalse);
    await c.retry(); expect(client.sent, hasLength(1));
    await c.discardOldEpoch(); expect(c.blocked, isFalse); c.dispose();
  });
  test('definitive stale revision clears pending and requires reviewing fresh desktop values', () async {
    final store = _Store(); final client = _Client(store)..error = const PairingFailure(LanErrorCode.revisionConflict);
    final c = controller(store, client);
    await c.submit(LanWriteOperation.customerCreate, snapshot, {});
    expect(c.pending, isNull); expect(c.message, contains('Dữ liệu đã đổi'));
    c.dispose();
  });
}
