import 'dart:convert';

class LicenseConfig {
  const LicenseConfig._();

  static const appCode = 'SALON';

  static const apiBaseUrl = String.fromEnvironment(
    'KEY_MANAGER_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:3101',
  );

  static const _offlinePublicKeysJson = String.fromEnvironment(
    'KEY_MANAGER_OFFLINE_PUBLIC_KEYS_JSON',
    defaultValue: '{}',
  );

  /// Compile-time key ring for Key Manager offline Ed25519 verification.
  ///
  /// Expected shape: {"key-id":"base64-raw-32-byte-ed25519-public-key"}.
  /// Keeping this as a dart-define makes local testing possible without
  /// hardcoding a production API URL or signing-key rotation into source.
  static Map<String, String> offlinePublicKeys() {
    try {
      final decoded = jsonDecode(_offlinePublicKeysJson);
      if (decoded is! Map) {
        return const {};
      }
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return const {};
    }
  }
}
