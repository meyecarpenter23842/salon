import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../database/salon_database.dart';
import '../models/audit_event.dart';

class SensitiveActionService {
  SensitiveActionService(this._database);

  static const _pinSaltKey = 'security.owner_pin_salt';
  static const _pinHashKey = 'security.owner_pin_hash';
  static const _actorNameKey = 'security.owner_actor_name';
  static const _sessionDuration = Duration(minutes: 5);

  final SalonDatabase _database;
  DateTime? _authorizedUntil;
  String _actorName = 'Owner';

  bool get isOwnerSessionActive {
    final until = _authorizedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  Future<bool> isProtectionConfigured() async {
    final db = await _database.database;
    final hash = await _readSetting(db, _pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  Future<void> configureOwnerPin(
    String pin, {
    String actorName = 'Owner',
  }) async {
    _validatePin(pin);
    final db = await _database.database;
    if (await isProtectionConfigured()) {
      throw StateError('PIN Owner đã được thiết lập.');
    }

    final salt = _randomSalt();
    final hash = await _derivePinHash(pin, salt);
    final now = DateTime.now();
    final normalizedActor =
        actorName.trim().isEmpty ? 'Owner' : actorName.trim();

    await db.transaction((tx) async {
      await _writeSetting(tx, _pinSaltKey, base64UrlEncode(salt), now);
      await _writeSetting(tx, _pinHashKey, hash, now);
      await _writeSetting(tx, _actorNameKey, normalizedActor, now);
    });

    _actorName = normalizedActor;
    _authorizedUntil = now.add(_sessionDuration);
    await _writeAudit(
      actorName: normalizedActor,
      action: 'security_setup',
      targetType: 'security',
      targetId: 'owner_pin',
      result: 'success',
      detail: 'Owner protection enabled',
    );
  }

  Future<bool> unlockOwner(String pin) async {
    final db = await _database.database;
    final configured = await isProtectionConfigured();
    if (!configured) {
      _authorizedUntil = DateTime.now().add(_sessionDuration);
      return true;
    }

    final actor = await _readSetting(db, _actorNameKey) ?? 'Owner';
    final ok = await _verifyPin(db, pin);
    await _writeAudit(
      actorName: actor,
      action: 'owner_unlock',
      targetType: 'security',
      targetId: 'owner_session',
      result: ok ? 'success' : 'denied',
      detail: ok ? 'Owner session unlocked' : 'Invalid owner PIN',
    );
    if (!ok) return false;

    _actorName = actor;
    _authorizedUntil = DateTime.now().add(_sessionDuration);
    return true;
  }

  Future<bool> changeOwnerPin({
    required String currentPin,
    required String newPin,
  }) async {
    _validatePin(newPin);
    final db = await _database.database;
    if (!await _verifyPin(db, currentPin)) {
      await _writeAudit(
        actorName: await _readSetting(db, _actorNameKey) ?? 'Owner',
        action: 'security_change_pin',
        targetType: 'security',
        targetId: 'owner_pin',
        result: 'denied',
        detail: 'Invalid current PIN',
      );
      return false;
    }

    final salt = _randomSalt();
    final hash = await _derivePinHash(newPin, salt);
    final now = DateTime.now();
    await db.transaction((tx) async {
      await _writeSetting(tx, _pinSaltKey, base64UrlEncode(salt), now);
      await _writeSetting(tx, _pinHashKey, hash, now);
    });
    _authorizedUntil = now.add(_sessionDuration);
    await _writeAudit(
      actorName: await _readSetting(db, _actorNameKey) ?? 'Owner',
      action: 'security_change_pin',
      targetType: 'security',
      targetId: 'owner_pin',
      result: 'success',
      detail: 'Owner PIN changed',
    );
    return true;
  }

  void lockOwnerSession() {
    _authorizedUntil = null;
  }

  /// Inventory authorization is checked before its atomic transaction begins.
  Future<String> authorizeInventoryAction(String action, String targetId) async {
    final protected = await isProtectionConfigured();
    if (protected && !isOwnerSessionActive) {
      await _writeAudit(actorName: 'Chưa xác thực', action: action,
        targetType: 'stock_document', targetId: targetId, result: 'denied',
        detail: 'Owner authorization required');
      throw StateError('Thao tác kho cần xác thực Owner.');
    }
    final db = await _database.database;
    return protected ? (await _readSetting(db, _actorNameKey) ?? _actorName)
      : 'Owner mặc định (chưa khóa PIN)';
  }

  Future<T> runSensitive<T>({
    required SensitiveAction action,
    required String targetType,
    required String targetId,
    required Future<T> Function() operation,
  }) async {
    final protected = await isProtectionConfigured();
    if (protected && !isOwnerSessionActive) {
      await _writeAudit(
        actorName: 'Chưa xác thực',
        action: action.databaseValue,
        targetType: targetType,
        targetId: targetId,
        result: 'denied',
        detail: 'Owner authorization required',
      );
      throw StateError(
        'Thao tác ${action.label} cần xác thực Owner.',
      );
    }

    final db = await _database.database;
    final actor = protected
        ? (await _readSetting(db, _actorNameKey) ?? _actorName)
        : 'Owner mặc định (chưa khóa PIN)';
    try {
      final result = await operation();
      await _writeAudit(
        actorName: actor,
        action: action.databaseValue,
        targetType: targetType,
        targetId: targetId,
        result: 'success',
        detail: protected ? 'Authorized owner action' : 'Protection not configured',
      );
      return result;
    } catch (error) {
      await _writeAudit(
        actorName: actor,
        action: action.databaseValue,
        targetType: targetType,
        targetId: targetId,
        result: 'failure',
        detail: error.runtimeType.toString(),
      );
      rethrow;
    }
  }

  Future<List<AuditEvent>> fetchAuditEvents({int limit = 50}) async {
    final db = await _database.database;
    final rows = await db.query(
      'audit_events',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows
        .map(
          (row) => AuditEvent(
            id: row['id']?.toString() ?? '',
            actorName: row['actor_name']?.toString() ?? '',
            action: row['action']?.toString() ?? '',
            targetType: row['target_type']?.toString() ?? '',
            targetId: row['target_id']?.toString() ?? '',
            result: row['result']?.toString() ?? '',
            detail: row['detail']?.toString() ?? '',
            createdAt:
                DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
          ),
        )
        .toList(growable: false);
  }

  Future<bool> _verifyPin(DatabaseExecutor db, String pin) async {
    final encodedSalt = await _readSetting(db, _pinSaltKey);
    final expected = await _readSetting(db, _pinHashKey);
    if (encodedSalt == null || expected == null) return false;
    try {
      final salt = base64Url.decode(encodedSalt);
      final actual = await _derivePinHash(pin, salt);
      return _constantTimeEquals(actual, expected);
    } catch (_) {
      return false;
    }
  }

  Future<String> _derivePinHash(String pin, List<int> salt) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 120000,
      bits: 256,
    );
    final secretKey = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return base64UrlEncode(await secretKey.extractBytes());
  }

  List<int> _randomSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256));
  }

  void _validatePin(String pin) {
    if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) {
      throw StateError('PIN Owner phải gồm 4-12 chữ số.');
    }
  }

  bool _constantTimeEquals(String left, String right) {
    final a = utf8.encode(left);
    final b = utf8.encode(right);
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<String?> _readSetting(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value']?.toString();
  }

  Future<void> _writeSetting(
    DatabaseExecutor db,
    String key,
    String value,
    DateTime now,
  ) {
    return db.insert(
      'app_settings',
      {
        'key': key,
        'value': value,
        'updated_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _writeAudit({
    required String actorName,
    required String action,
    required String targetType,
    required String targetId,
    required String result,
    required String detail,
  }) async {
    final db = await _database.database;
    final now = DateTime.now();
    await db.insert(
      'audit_events',
      {
        'id': 'audit-${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 20)}',
        'actor_name': actorName,
        'action': action,
        'target_type': targetType,
        'target_id': targetId,
        'result': result,
        'detail': detail,
        'created_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }
}
