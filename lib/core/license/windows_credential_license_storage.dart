import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:win32/win32.dart';

import 'license_models.dart';
import 'license_storage.dart';

class WindowsCredentialLicenseStorage implements LicenseStorage {
  static const _deviceTarget = 'SalonManager/KeyManager/v1/device-id';
  static const _licenseTarget = 'SalonManager/KeyManager/v1/license-state';
  static const _credentialUser = 'SalonManager';

  @override
  Future<String> loadOrCreateDeviceId({String? legacyDeviceId}) async {
    final existing = _readCredential(_deviceTarget)?.trim();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final legacy = legacyDeviceId?.trim() ?? '';
    final deviceId = legacy.isNotEmpty ? legacy : const Uuid().v4();
    _writeCredential(_deviceTarget, deviceId);
    return deviceId;
  }

  @override
  Future<StoredLicenseState?> readLicense() async {
    final raw = _readCredential(_licenseTarget);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Local license state must be an object');
    }
    return StoredLicenseState.fromJson(Map<String, dynamic>.from(decoded));
  }

  @override
  Future<void> writeLicense(StoredLicenseState state) async {
    _writeCredential(_licenseTarget, jsonEncode(state.toJson()));
  }

  String? _readCredential(String target) {
    _requireWindows();
    return using((arena) {
      final targetName = arena.pcwstr(target);
      final credentialPointer = arena<Pointer<CREDENTIAL>>();
      final result = CredRead(
        targetName,
        CRED_TYPE_GENERIC,
        credentialPointer,
      );
      if (!result.value) {
        if (result.error == ERROR_NOT_FOUND) {
          return null;
        }
        throw StateError(
          'Windows Credential Manager read failed (${result.error})',
        );
      }

      final nativeCredential = credentialPointer.value;
      try {
        final credential = nativeCredential.ref;
        final bytes = credential.CredentialBlob.asTypedList(
          credential.CredentialBlobSize,
        );
        return utf8.decode(List<int>.from(bytes));
      } finally {
        CredFree(nativeCredential);
      }
    });
  }

  void _writeCredential(String target, String value) {
    _requireWindows();
    using((arena) {
      final bytes = utf8.encode(value);
      final blob = bytes.toNative(allocator: arena);
      final targetName = arena.pwstr(target);
      final userName = arena.pwstr(_credentialUser);
      final credential = arena<CREDENTIAL>();

      credential.ref
        ..Type = CRED_TYPE_GENERIC
        ..TargetName = targetName
        ..Persist = CRED_PERSIST_LOCAL_MACHINE
        ..UserName = userName
        ..CredentialBlob = blob
        ..CredentialBlobSize = bytes.length;

      final result = CredWrite(credential, 0);
      if (!result.value) {
        throw StateError(
          'Windows Credential Manager write failed (${result.error})',
        );
      }
    });
  }

  void _requireWindows() {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'Key Manager credential storage is supported on Windows only.',
      );
    }
  }
}
