import 'dart:convert';

import 'package:flutter/services.dart';
import '../../core/lan/lan_write_contract.dart';

class CompanionCredential {
  const CompanionCredential(this.pin, this.token, {this.pendingCommand});
  final String pin;
  final String token;
  final LanWriteCommand? pendingCommand;
  CompanionCredential withPending(LanWriteCommand? command) =>
    CompanionCredential(pin, token, pendingCommand: command);
}

abstract interface class CompanionCredentialStore {
  Future<CompanionCredential?> read();
  Future<void> write(CompanionCredential credential);
  Future<void> clear();
}

/// Native Android Keystore-backed encrypted storage, separate from URL preferences.
class AndroidCompanionCredentialStore implements CompanionCredentialStore {
  const AndroidCompanionCredentialStore();
  static const _channel = MethodChannel('salon/companion_credentials');
  @override
  Future<CompanionCredential?> read() async {
    final text = await _channel.invokeMethod<String>('read').timeout(const Duration(seconds: 3));
    if (text == null) return null;
    final json = jsonDecode(text) as Map;
    final pin = json['pin'] as String;
    final token = json['token'] as String;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(pin) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      throw const FormatException('Invalid credential');
    }
    return CompanionCredential(pin, token, pendingCommand: json['pendingCommand'] == null ? null :
      LanWriteCommand.fromJson(Map<String, dynamic>.from(json['pendingCommand'] as Map)));
  }

  @override
  Future<void> write(CompanionCredential credential) =>
      _channel.invokeMethod<void>('write', jsonEncode({
        'pin': credential.pin, 'token': credential.token,
        if (credential.pendingCommand != null) 'pendingCommand': credential.pendingCommand!.toJson(),
      })).timeout(const Duration(seconds: 3));
  @override
  Future<void> clear() => _channel.invokeMethod<void>('clear').timeout(const Duration(seconds: 3));
}
