import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/license/license_models.dart';
import 'package:salonmanager/core/license/offline_license_verifier.dart';

void main() {
  final issuedAt = DateTime.utc(2026, 9, 10, 12);
  final validUntil = issuedAt.add(const Duration(hours: 1));

  test('accepts valid Ed25519 token bound to Salon license and device', () async {
    final fixture = await _signedFixture(
      issuedAt: issuedAt,
      validUntil: validUntil,
    );
    final verifier = Ed25519OfflineLicenseVerifier(
      publicKeys: {'test-key': fixture.publicKeyBase64},
    );

    final result = await verifier.verify(
      state: fixture.state,
      wallClockNow: issuedAt.add(const Duration(minutes: 15)),
    );

    expect(result.allowed, isTrue);
    expect(result.trustedHighWater, issuedAt.add(const Duration(minutes: 15)));
    expect(result.remaining, const Duration(minutes: 45));
  });

  test('rejects cryptographically valid token for another device', () async {
    final fixture = await _signedFixture(
      issuedAt: issuedAt,
      validUntil: validUntil,
      tokenDeviceId: 'other-device',
    );
    final verifier = Ed25519OfflineLicenseVerifier(
      publicKeys: {'test-key': fixture.publicKeyBase64},
    );

    final result = await verifier.verify(
      state: fixture.state,
      wallClockNow: issuedAt.add(const Duration(minutes: 5)),
    );

    expect(result.allowed, isFalse);
    expect(result.message, contains('binding mismatch'));
  });

  test('rejects wall-clock rollback beyond tolerance', () async {
    final fixture = await _signedFixture(
      issuedAt: issuedAt,
      validUntil: validUntil,
    );
    final verifier = Ed25519OfflineLicenseVerifier(
      publicKeys: {'test-key': fixture.publicKeyBase64},
    );

    final result = await verifier.verify(
      state: fixture.state,
      wallClockNow: issuedAt.subtract(const Duration(minutes: 6)),
    );

    expect(result.allowed, isFalse);
    expect(result.message, contains('Đồng hồ Windows'));
  });

  test('rejects token once offline grace is exhausted', () async {
    final fixture = await _signedFixture(
      issuedAt: issuedAt,
      validUntil: validUntil,
    );
    final verifier = Ed25519OfflineLicenseVerifier(
      publicKeys: {'test-key': fixture.publicKeyBase64},
    );

    final result = await verifier.verify(
      state: fixture.state,
      wallClockNow: validUntil,
    );

    expect(result.allowed, isFalse);
    expect(result.message, contains('đã hết'));
  });
}

Future<_SignedFixture> _signedFixture({
  required DateTime issuedAt,
  required DateTime validUntil,
  String tokenDeviceId = 'device-1',
}) async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final publicKey = await keyPair.extractPublicKey();

  final header = {
    'alg': 'EdDSA',
    'typ': 'KM-OFFLINE',
    'kid': 'test-key',
  };
  final payload = {
    'schema_version': 1,
    'license_id': 'license-1',
    'app_id': 'app-salon',
    'app_code': 'SALON',
    'device_id': tokenDeviceId,
    'issued_at': issuedAt.toIso8601String(),
    'expires_at': null,
    'offline_valid_until': validUntil.toIso8601String(),
  };
  final encodedHeader = _base64UrlNoPadding(utf8.encode(jsonEncode(header)));
  final encodedPayload = _base64UrlNoPadding(utf8.encode(jsonEncode(payload)));
  final signingInput = '$encodedHeader.$encodedPayload';
  final signature = await algorithm.sign(
    utf8.encode(signingInput),
    keyPair: keyPair,
  );
  final token = '$signingInput.${_base64UrlNoPadding(signature.bytes)}';

  return _SignedFixture(
    publicKeyBase64: base64.encode(publicKey.bytes),
    state: StoredLicenseState(
      licenseKey: 'SALON-VALID-KEY',
      licenseId: 'license-1',
      applicationId: 'app-salon',
      deviceId: 'device-1',
      offlineToken: token,
      serverTimeAtSync: issuedAt,
      wallClockAtSync: issuedAt,
      trustedHighWater: issuedAt,
    ),
  );
}

String _base64UrlNoPadding(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

class _SignedFixture {
  const _SignedFixture({
    required this.publicKeyBase64,
    required this.state,
  });

  final String publicKeyBase64;
  final StoredLicenseState state;
}
