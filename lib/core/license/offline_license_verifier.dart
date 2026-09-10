import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'license_config.dart';
import 'license_models.dart';

class OfflineLicenseCheck {
  const OfflineLicenseCheck._({
    required this.allowed,
    this.message,
    this.trustedHighWater,
    this.remaining,
  });

  const OfflineLicenseCheck.allowed({
    required DateTime trustedHighWater,
    required Duration remaining,
  }) : this._(
         allowed: true,
         trustedHighWater: trustedHighWater,
         remaining: remaining,
       );

  const OfflineLicenseCheck.denied(String message)
    : this._(allowed: false, message: message);

  final bool allowed;
  final String? message;
  final DateTime? trustedHighWater;
  final Duration? remaining;
}

abstract interface class OfflineLicenseVerifier {
  Future<OfflineLicenseCheck> verify({
    required StoredLicenseState state,
    required DateTime wallClockNow,
  });
}

class Ed25519OfflineLicenseVerifier implements OfflineLicenseVerifier {
  Ed25519OfflineLicenseVerifier({
    Map<String, String>? publicKeys,
    this.clockRollbackTolerance = const Duration(minutes: 5),
  }) : _publicKeys = publicKeys ?? LicenseConfig.offlinePublicKeys();

  final Map<String, String> _publicKeys;
  final Duration clockRollbackTolerance;

  @override
  Future<OfflineLicenseCheck> verify({
    required StoredLicenseState state,
    required DateTime wallClockNow,
  }) async {
    final token = state.offlineToken?.trim() ?? '';
    if (token.isEmpty) {
      return const OfflineLicenseCheck.denied(
        'Máy đang offline và chưa có quyền sử dụng offline hợp lệ.',
      );
    }
    if (_publicKeys.isEmpty) {
      return const OfflineLicenseCheck.denied(
        'Bản Salon này chưa cấu hình public key để xác minh license offline.',
      );
    }

    try {
      final parts = token.split('.');
      if (parts.length != 3 || parts.any((part) => part.isEmpty)) {
        throw const FormatException('Offline token must have three segments');
      }

      final header = _decodeJson(parts[0]);
      final payload = _decodeJson(parts[1]);
      if (header['alg'] != 'EdDSA' ||
          header['typ'] != 'KM-OFFLINE' ||
          header['kid'] is! String) {
        throw const FormatException('Offline token header is unsupported');
      }
      if (payload['schema_version'] != 1) {
        throw const FormatException('Offline token schema is unsupported');
      }

      final keyId = (header['kid'] as String).trim();
      final encodedPublicKey = _publicKeys[keyId];
      if (encodedPublicKey == null) {
        throw FormatException('Unknown offline signing key: $keyId');
      }
      final publicKeyBytes = _decodeFlexibleBase64(encodedPublicKey);
      if (publicKeyBytes.length != 32) {
        throw const FormatException(
          'Ed25519 public key must contain exactly 32 bytes',
        );
      }

      final signatureBytes = _decodeBase64Url(parts[2]);
      final signature = Signature(
        signatureBytes,
        publicKey: SimplePublicKey(
          publicKeyBytes,
          type: KeyPairType.ed25519,
        ),
      );
      final verified = await Ed25519().verify(
        utf8.encode('${parts[0]}.${parts[1]}'),
        signature: signature,
      );
      if (!verified) {
        throw const FormatException('Offline token signature is invalid');
      }

      _requireBinding(payload, 'app_code', LicenseConfig.appCode);
      _requireBinding(payload, 'license_id', state.licenseId);
      _requireBinding(payload, 'app_id', state.applicationId);
      _requireBinding(payload, 'device_id', state.deviceId);

      final issuedAt = _date(payload['issued_at'], 'issued_at');
      final offlineValidUntil = _date(
        payload['offline_valid_until'],
        'offline_valid_until',
      );
      final expiresAt = payload['expires_at'] == null
          ? null
          : _date(payload['expires_at'], 'expires_at');

      if (offlineValidUntil.isBefore(issuedAt)) {
        throw const FormatException('Offline validity precedes issue time');
      }
      if (expiresAt != null && offlineValidUntil.isAfter(expiresAt)) {
        throw const FormatException('Offline validity exceeds license expiry');
      }
      if (issuedAt != state.serverTimeAtSync) {
        throw const FormatException('Offline token does not match sync anchor');
      }

      final now = wallClockNow.toUtc();
      final rollbackBoundary = state.wallClockAtSync.subtract(
        clockRollbackTolerance,
      );
      if (now.isBefore(rollbackBoundary)) {
        return const OfflineLicenseCheck.denied(
          'Đồng hồ Windows có dấu hiệu bị lùi. Cần kết nối mạng để xác minh lại license.',
        );
      }

      var wallElapsed = now.difference(state.wallClockAtSync);
      if (wallElapsed.isNegative) {
        wallElapsed = Duration.zero;
      }
      var trustedNow = state.serverTimeAtSync.add(wallElapsed);
      if (trustedNow.isBefore(state.trustedHighWater)) {
        trustedNow = state.trustedHighWater;
      }

      if (!trustedNow.isBefore(offlineValidUntil) ||
          (expiresAt != null && !trustedNow.isBefore(expiresAt))) {
        return const OfflineLicenseCheck.denied(
          'Thời gian sử dụng offline của license đã hết. Cần kết nối mạng để xác minh lại.',
        );
      }

      return OfflineLicenseCheck.allowed(
        trustedHighWater: trustedNow,
        remaining: offlineValidUntil.difference(trustedNow),
      );
    } on FormatException catch (error) {
      return OfflineLicenseCheck.denied(
        'Không thể xác minh license offline (${error.message}).',
      );
    } catch (_) {
      return const OfflineLicenseCheck.denied(
        'Không thể xác minh license offline. Cần kết nối mạng để tiếp tục.',
      );
    }
  }

  Map<String, dynamic> _decodeJson(String segment) {
    final decoded = jsonDecode(utf8.decode(_decodeBase64Url(segment)));
    if (decoded is! Map) {
      throw const FormatException('Offline token JSON must be an object');
    }
    return Map<String, dynamic>.from(decoded);
  }

  List<int> _decodeBase64Url(String input) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(input)) {
      throw const FormatException('Invalid base64url segment');
    }
    return base64Url.decode(_withPadding(input));
  }

  List<int> _decodeFlexibleBase64(String input) {
    final normalized = input.trim().replaceAll('-', '+').replaceAll('_', '/');
    return base64.decode(_withPadding(normalized));
  }

  String _withPadding(String input) {
    final missing = input.length % 4;
    if (missing == 0) {
      return input;
    }
    return input.padRight(input.length + (4 - missing), '=');
  }

  void _requireBinding(
    Map<String, dynamic> payload,
    String field,
    String expected,
  ) {
    if (payload[field] != expected) {
      throw FormatException('Offline token binding mismatch: $field');
    }
  }

  DateTime _date(Object? value, String field) {
    if (value is! String) {
      throw FormatException('$field must be a timestamp');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('$field must be a timestamp');
    }
    return parsed.toUtc();
  }
}
