import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'lan_contract.dart';

enum PhoneWriteRole { none, staff, cashier, owner }

enum LanWriteOperation {
  customerCreate, customerUpdate, appointmentCreate, appointmentUpdate,
  appointmentStatus, sessionCreate, sessionOpenAppointment, sessionSelectCustomer,
  sessionAddService, sessionAddProduct, sessionQuantity, sessionRemoveLine,
  sessionAssignEmployee, sessionPayment, sessionDiscount, sessionPrice, sessionCheckout,
}

extension LanWritePolicy on LanWriteOperation {
  bool allows(PhoneWriteRole role) {
    if (role == PhoneWriteRole.none) return false;
    if (this == LanWriteOperation.sessionDiscount || this == LanWriteOperation.sessionPrice) {
      return role == PhoneWriteRole.owner;
    }
    if (this == LanWriteOperation.sessionCheckout || this == LanWriteOperation.sessionPayment) {
      return role == PhoneWriteRole.cashier || role == PhoneWriteRole.owner;
    }
    return true;
  }
  bool get creates => this == LanWriteOperation.customerCreate ||
      this == LanWriteOperation.appointmentCreate || this == LanWriteOperation.sessionCreate;
  String get resourceType => switch (this) {
    LanWriteOperation.customerCreate || LanWriteOperation.customerUpdate => 'customer',
    LanWriteOperation.appointmentCreate || LanWriteOperation.appointmentUpdate ||
      LanWriteOperation.appointmentStatus || LanWriteOperation.sessionOpenAppointment => 'appointment',
    _ => 'session',
  };
}

/// Client-supplied roles and selected desktop sessions are never accepted.
class LanWriteCommand {
  LanWriteCommand({required this.commandId, required this.operation,
    required this.expectedEpoch, required this.payload, this.targetId, this.expectedRevision}) {
    LanContract.validateIdentity(commandId, 'commandId');
    LanContract.validateIdentity(expectedEpoch, 'epoch');
    if (targetId != null) LanContract.validateIdentity(targetId!, 'targetId');
    if (operation.creates ? targetId != null || expectedRevision != null
        : targetId == null || expectedRevision == null || expectedRevision! < 1) {
      throw const FormatException('Invalid resource precondition');
    }
    _canonical(payload, 0);
    if (utf8.encode(jsonEncode(toJson())).length > 16384) {
      throw const FormatException('Command too large');
    }
  }
  final String commandId;
  final LanWriteOperation operation;
  final String expectedEpoch;
  final String? targetId;
  final int? expectedRevision;
  final Map<String, dynamic> payload;
  Map<String, Object?> toJson() => {
    'commandId': commandId, 'operation': operation.name, 'expectedEpoch': expectedEpoch,
    'targetId': targetId, 'expectedRevision': expectedRevision, 'payload': payload,
  };
  String get signature => sha256.convert(utf8.encode(jsonEncode(_canonical(toJson(), 0)))).toString();

  factory LanWriteCommand.fromJson(Map<String, dynamic> json) {
    const keys = ['commandId', 'operation', 'expectedEpoch', 'targetId', 'expectedRevision', 'payload'];
    if (json.length != keys.length || json.keys.any((k) => !keys.contains(k)) ||
        json['commandId'] is! String || json['operation'] is! String ||
        json['expectedEpoch'] is! String || json['payload'] is! Map<String, dynamic> ||
        (json['targetId'] != null && json['targetId'] is! String) ||
        (json['expectedRevision'] != null && json['expectedRevision'] is! int)) {
      throw const FormatException('Invalid command');
    }
    return LanWriteCommand(commandId: json['commandId'] as String,
      operation: LanWriteOperation.values.byName(json['operation'] as String),
      expectedEpoch: json['expectedEpoch'] as String, targetId: json['targetId'] as String?,
      expectedRevision: json['expectedRevision'] as int?,
      payload: Map<String, dynamic>.from(json['payload'] as Map));
  }

  static Object? _canonical(Object? value, int depth) {
    if (depth > 6) throw const FormatException('Command nesting');
    if (value == null || value is bool || value is int) return value;
    if (value is String) {
      if (value.length > 4000) throw const FormatException('Command string');
      return value;
    }
    if (value is List) {
      if (value.length > 100) throw const FormatException('Command list');
      return value.map((v) => _canonical(v, depth + 1)).toList();
    }
    if (value is Map<String, dynamic>) {
      if (value.length > 50) throw const FormatException('Command fields');
      final keys = value.keys.toList()..sort();
      return {for (final key in keys) key: _canonical(value[key], depth + 1)};
    }
    throw const FormatException('Unsupported command value');
  }
}

class LanWriteResult {
  const LanWriteResult({required this.id, required this.type, required this.revision});
  final String id;
  final String type;
  final int revision;
  Map<String, Object> toJson() => {'id': id, 'type': type, 'revision': revision};
  factory LanWriteResult.fromJson(Map<String, dynamic> json) {
    if (json['id'] is! String || json['type'] is! String || json['revision'] is! int ||
        (json['revision'] as int) < 1 ||
        !['customer', 'appointment', 'session', 'invoice'].contains(json['type'])) {
      throw const FormatException('Invalid command result');
    }
    LanContract.validateIdentity(json['id'] as String, 'id');
    return LanWriteResult(id: json['id'] as String, type: json['type'] as String,
      revision: json['revision'] as int);
  }
}
