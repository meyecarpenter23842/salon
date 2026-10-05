import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/salon_database.dart';
import '../models/entity_id.dart';
import 'lan_contract.dart';
import 'lan_pairing.dart';
import 'lan_write_contract.dart';

class LanMutationTarget {
  const LanMutationTarget(this.id, this.type);
  final String id;
  final String type;
}

/// The one command boundary for all mobile domain mutations. Repositories join
/// its transaction through a scoped SalonDatabase. Successful results are kept
/// permanently; no TTL can accidentally turn an old retry into a second write.
class LanWriteEngine {
  LanWriteEngine(this.database);
  final SalonDatabase database;

  Future<int> revision(DatabaseExecutor db, String type, String id) async {
    final rows = await db.query('lan_resource_revisions', columns: ['revision'],
      where: 'resource_type = ? AND resource_id = ?',
      whereArgs: [type == 'invoice' ? 'session' : type, id], limit: 1);
    if (rows.isEmpty) throw const PairingFailure(LanErrorCode.notFound);
    return rows.single['revision'] as int;
  }

  Future<LanWriteResult?> result(String deviceId, String commandId) async {
    LanContract.validateIdentity(deviceId, 'device');
    LanContract.validateIdentity(commandId, 'command');
    final db = await database.database;
    final rows = await db.query('lan_commands', columns: ['result_json'],
      where: 'device_id = ? AND command_id = ?', whereArgs: [deviceId, commandId], limit: 1);
    return rows.isEmpty ? null : LanWriteResult.fromJson(
      jsonDecode(rows.single['result_json'] as String) as Map<String, dynamic>);
  }

  Future<LanWriteResult> execute(PairedPhone phone, LanWriteCommand command,
      Future<LanMutationTarget> Function(SalonDatabase scope) operation) async {
    if (phone.state != PhoneAccess.approved || !phone.canReadSalon ||
        !command.operation.allows(phone.writeRole)) {
      throw const PairingFailure(LanErrorCode.forbidden);
    }
    final db = await database.database;
    final signature = command.signature;
    try {
      return await db.transaction((tx) async {
        final saved = await tx.query('lan_commands', columns: ['signature', 'result_json'],
          where: 'device_id = ? AND command_id = ?',
          whereArgs: [phone.id, command.commandId], limit: 1);
        if (saved.isNotEmpty) {
          if (saved.single['signature'] != signature) {
            throw const PairingFailure(LanErrorCode.commandConflict);
          }
          return LanWriteResult.fromJson(
            jsonDecode(saved.single['result_json'] as String) as Map<String, dynamic>);
        }
        // Replay lookup precedes revision/epoch checks, including after restart.
        if (command.expectedEpoch != database.runtimeEpoch) {
          throw const PairingFailure(LanErrorCode.revisionConflict);
        }
        final count = (await tx.rawQuery('SELECT COUNT(*) AS n FROM lan_commands')).single['n'] as int;
        if (count >= 100000) throw const PairingFailure(LanErrorCode.rateLimited);
        if (!command.operation.creates) {
          await _ensureTarget(tx, command);
          if (await revision(tx, command.operation.resourceType, command.targetId!) != command.expectedRevision) {
            throw const PairingFailure(LanErrorCode.revisionConflict);
          }
        }
        final scope = SalonDatabase.forTransaction(tx, database.runtimeEpoch);
        final target = await operation(scope);
        LanContract.validateIdentity(target.id, 'result');
        final value = LanWriteResult(id: target.id, type: target.type,
          revision: await revision(tx, target.type, target.id));
        // Validate before persisting any user-visible success.
        LanWriteResult.fromJson(value.toJson());
        await tx.insert('lan_commands', {
          'device_id': phone.id, 'command_id': command.commandId, 'signature': signature,
          'result_json': jsonEncode(value.toJson()), 'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        await _audit(tx, phone, command, 'success', 'Committed device command');
        return value;
      });
    } catch (error) {
      final code = error is PairingFailure ? error.code
          : error is StateError || error is ArgumentError ? LanErrorCode.businessRule
          : LanErrorCode.internal;
      try {
        await _audit(db, phone, command, code == LanErrorCode.forbidden ? 'denied' : 'failure', code.wireName);
      } catch (_) { /* Audit failure cannot turn a rolled-back command into success. */ }
      throw PairingFailure(code);
    }
  }

  Future<void> _ensureTarget(DatabaseExecutor db, LanWriteCommand command) async {
    final type = command.operation.resourceType;
    final id = command.targetId!;
    final table = type == 'customer' ? 'customers' : type == 'appointment' ? 'appointments' : 'invoices';
    final rows = await db.query(table, columns: type == 'session' ? ['id', 'paid_at'] : ['id'],
      where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty) {
      if (type == 'session' && rows.single['paid_at'] != null) {
        throw const PairingFailure(LanErrorCode.alreadyPaid);
      }
      return;
    }
    if (type == 'session') {
      final states = await db.query('app_settings', columns: ['key'],
        where: 'key = ?', whereArgs: [id == 'invoice-draft-001'
          ? 'invoice_draft_state_v1' : 'invoice_draft_state_v2:$id'], limit: 1);
      if (states.isNotEmpty) return;
    }
    throw const PairingFailure(LanErrorCode.notFound);
  }

  Future<void> _audit(DatabaseExecutor db, PairedPhone phone, LanWriteCommand command,
      String result, String detail) => db.insert('audit_events', {
    'id': EntityId.create('audit'), 'actor_name': 'Phone ${phone.id.substring(0, 12)}',
    'action': command.operation.name, 'target_type': command.operation.resourceType,
    'target_id': command.targetId ?? 'new', 'result': result, 'detail': detail,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  }).then((_) {});
}
