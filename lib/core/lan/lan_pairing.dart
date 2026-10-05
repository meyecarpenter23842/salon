import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'lan_contract.dart';

String newDeviceSecret() {
  final random = Random.secure();
  return List.generate(32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

class PairingFailure implements Exception {
  const PairingFailure(this.code);
  final LanErrorCode code;
}

enum PhoneAccess { pending, approved, denied, revoked, expired }

class PairedPhone {
  const PairedPhone(this.id, this.name, this.state, this.createdAt);
  final String id;
  final String name;
  final PhoneAccess state;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
    'id': id, 'name': name, 'state': state.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory PairedPhone.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(id) ||
        name is! String || name.isEmpty || name.length > 60) {
      throw const FormatException('Invalid device');
    }
    return PairedPhone(id, name,
      PhoneAccess.values.byName(json['state'] as String),
      DateTime.parse(json['createdAt'] as String).toUtc());
  }

  PairedPhone withState(PhoneAccess value) => PairedPhone(id, name, value, createdAt);
}

/// Machine-only device hashes; no token, PIN or business SQLite dependency.
/// Transitions are serialized and published only after durable commit.
class LanPairingRegistry extends ChangeNotifier {
  LanPairingRegistry({required this.file, DateTime Function()? clock})
      : clock = clock ?? DateTime.now;
  final File file;
  final DateTime Function() clock;
  final Map<String, PairedPhone> _phones = {};
  Future<void> _queue = Future<void>.value();
  String? _code;
  DateTime? _codeExpiry;
  bool _active = false;

  List<PairedPhone> get phones => List.unmodifiable(_phones.values.map(_effective));
  String? get code => _active && _codeExpiry != null && clock().isBefore(_codeExpiry!) ? _code : null;
  DateTime? get codeExpiry => _codeExpiry;
  bool get active => _active;
  Future<void> get settled => _queue;

  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _queue.then((_) => operation());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> load() => _serial(() async {
    if (await file.exists()) {
      if (await file.length() > 65536) throw const FormatException('Device store too large');
      final json = jsonDecode(await file.readAsString());
      if (json is! Map || json['version'] != 1 || json['phones'] is! List) {
        throw const FormatException('Invalid device store');
      }
      final entries = json['phones'] as List;
      if (entries.length > 100) throw const FormatException('Too many devices');
      final restored = <String, PairedPhone>{};
      for (final entry in entries) {
        final phone = PairedPhone.fromJson(Map<String, dynamic>.from(entry as Map));
        restored[phone.id] = phone.state == PhoneAccess.pending
            ? phone.withState(PhoneAccess.expired) : phone;
      }
      _phones.clear();
      _phones.addAll(restored);
    }
    notifyListeners();
  });

  void setActive(bool value) {
    _active = value;
    _code = null;
    _codeExpiry = null;
    notifyListeners();
  }

  Future<String> createCode() => _serial(() async {
    if (!_active) throw const PairingFailure(LanErrorCode.unavailable);
    final random = Random.secure();
    _code = List.generate(8, (_) => random.nextInt(10)).join();
    _codeExpiry = clock().add(const Duration(minutes: 5));
    notifyListeners();
    return _code!;
  });

  String _identity(String token) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      throw const PairingFailure(LanErrorCode.unauthenticated);
    }
    return sha256.convert(utf8.encode(token)).toString();
  }

  Future<void> _save(Map<String, PairedPhone> next) async {
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.tmp');
    await pending.writeAsString(jsonEncode({
      'version': 1, 'phones': next.values.map((p) => p.toJson()).toList(),
    }), flush: true);
    await pending.rename(file.path);
    _phones.clear();
    _phones.addAll(next);
    notifyListeners();
  }

  Future<PairedPhone> request(String pairingCode, String name, String token) => _serial(() async {
    if (!_active) throw const PairingFailure(LanErrorCode.unavailable);
    final id = _identity(token);
    final existing = _phones[id];
    // Retrying cannot consume a second code or reset a revoked identity.
    if (existing != null) return _effective(existing);
    name = name.trim();
    if (name.isEmpty || name.length > 60 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      throw const PairingFailure(LanErrorCode.invalidRequest);
    }
    if (code == null || pairingCode != code || !RegExp(r'^\d{8}$').hasMatch(pairingCode)) {
      throw const PairingFailure(LanErrorCode.forbidden);
    }
    if (_phones.length >= 100) throw const PairingFailure(LanErrorCode.rateLimited);
    final phone = PairedPhone(id, name, PhoneAccess.pending, clock().toUtc());
    await _save({..._phones, id: phone});
    _code = null;
    _codeExpiry = null;
    notifyListeners();
    return phone;
  });

  PairedPhone _effective(PairedPhone phone) {
    if (phone.state == PhoneAccess.pending &&
        !clock().isBefore(phone.createdAt.add(const Duration(minutes: 5)))) {
      return phone.withState(PhoneAccess.expired);
    }
    return phone;
  }

  Future<PairedPhone> status(String token, {bool requireApproved = false}) => _serial(() async {
    if (!_active) throw const PairingFailure(LanErrorCode.unavailable);
    final phone = _phones[_identity(token)];
    if (phone == null) throw const PairingFailure(LanErrorCode.unauthenticated);
    final effective = _effective(phone);
    if (requireApproved && effective.state != PhoneAccess.approved) {
      throw const PairingFailure(LanErrorCode.forbidden);
    }
    return effective;
  });

  // Desktop owner actions only; there is no HTTP administration route.
  Future<void> decide(String id, PhoneAccess state) => _serial(() async {
    if (!_active) throw const PairingFailure(LanErrorCode.unavailable);
    final phone = _phones[id];
    if (phone == null) throw const PairingFailure(LanErrorCode.notFound);
    final current = _effective(phone);
    final allowed = current.state == PhoneAccess.pending &&
        (state == PhoneAccess.approved || state == PhoneAccess.denied) ||
        current.state == PhoneAccess.approved && state == PhoneAccess.revoked;
    if (!allowed) throw const PairingFailure(LanErrorCode.forbidden);
    await _save({..._phones, id: phone.withState(state)});
  });
}
