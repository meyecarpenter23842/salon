class LicenseRuntimeContext {
  const LicenseRuntimeContext({
    required this.deviceId,
    required this.deviceName,
    required this.os,
    required this.appVersion,
  });

  final String deviceId;
  final String deviceName;
  final String os;
  final String appVersion;
}

enum LicenseAccessStatus {
  activationRequired,
  allowedOnline,
  allowedOffline,
  blocked,
}

class LicenseGateResult {
  const LicenseGateResult({
    required this.status,
    this.message,
    this.requestId,
    this.offlineRemaining,
  });

  final LicenseAccessStatus status;
  final String? message;
  final String? requestId;
  final Duration? offlineRemaining;

  bool get isAllowed =>
      status == LicenseAccessStatus.allowedOnline ||
      status == LicenseAccessStatus.allowedOffline;
}

class LicenseOfflineEntitlement {
  const LicenseOfflineEntitlement({
    required this.token,
    required this.keyId,
    required this.issuedAt,
    required this.offlineValidUntil,
  });

  final String token;
  final String keyId;
  final DateTime issuedAt;
  final DateTime offlineValidUntil;
}

class LicenseServerSnapshot {
  const LicenseServerSnapshot({
    required this.status,
    required this.serverTime,
    required this.applicationId,
    required this.appCode,
    required this.licenseId,
    required this.deviceId,
    required this.deviceStatus,
    required this.requestId,
    this.licenseType,
    this.licenseExpiresAt,
    this.maxDevices,
    this.deviceActivatedAt,
    this.deviceLastSeenAt,
    this.offline,
  });

  final String status;
  final DateTime serverTime;
  final String applicationId;
  final String appCode;
  final String licenseId;
  final String? licenseType;
  final DateTime? licenseExpiresAt;
  final int? maxDevices;
  final String deviceId;
  final String deviceStatus;
  final DateTime? deviceActivatedAt;
  final DateTime? deviceLastSeenAt;
  final String requestId;
  final LicenseOfflineEntitlement? offline;

  factory LicenseServerSnapshot.fromJson(Map<String, dynamic> json) {
    final application = _object(json['application'], 'application');
    final license = _object(json['license'], 'license');
    final device = _object(json['device'], 'device');
    final offlineJson = json['offline'];

    return LicenseServerSnapshot(
      status: _text(json['status'], 'status'),
      serverTime: _date(json['serverTime'], 'serverTime'),
      applicationId: _text(application['id'], 'application.id'),
      appCode: _text(application['appCode'], 'application.appCode'),
      licenseId: _text(license['id'], 'license.id'),
      licenseType: _optionalText(license['type'], 'license.type'),
      licenseExpiresAt: _optionalDate(license['expiresAt'], 'license.expiresAt'),
      maxDevices: _optionalPositiveInt(license['maxDevices'], 'license.maxDevices'),
      deviceId: _text(device['deviceId'], 'device.deviceId'),
      deviceStatus: _text(device['status'], 'device.status'),
      deviceActivatedAt: _optionalDate(device['activatedAt'], 'device.activatedAt'),
      deviceLastSeenAt: _optionalDate(device['lastSeenAt'], 'device.lastSeenAt'),
      requestId: _text(json['requestId'], 'requestId'),
      offline: offlineJson == null
          ? null
          : LicenseOfflineEntitlement(
              token: _text(
                _object(offlineJson, 'offline')['token'],
                'offline.token',
              ),
              keyId: _text(
                _object(offlineJson, 'offline')['keyId'],
                'offline.keyId',
              ),
              issuedAt: _date(
                _object(offlineJson, 'offline')['issuedAt'],
                'offline.issuedAt',
              ),
              offlineValidUntil: _date(
                _object(offlineJson, 'offline')['offlineValidUntil'],
                'offline.offlineValidUntil',
              ),
            ),
    );
  }
}

class StoredLicenseState {
  const StoredLicenseState({
    required this.licenseKey,
    required this.licenseId,
    required this.applicationId,
    required this.deviceId,
    required this.serverTimeAtSync,
    required this.wallClockAtSync,
    required this.trustedHighWater,
    this.offlineToken,
    this.licenseType,
    this.licenseExpiresAt,
    this.maxDevices,
    this.deviceName,
    this.deviceActivatedAt,
    this.deviceLastSeenAt,
  });

  final String licenseKey;
  final String licenseId;
  final String applicationId;
  final String deviceId;
  final String? offlineToken;
  final String? licenseType;
  final DateTime? licenseExpiresAt;
  final int? maxDevices;
  final String? deviceName;
  final DateTime? deviceActivatedAt;
  final DateTime? deviceLastSeenAt;
  final DateTime serverTimeAtSync;
  final DateTime wallClockAtSync;
  final DateTime trustedHighWater;

  StoredLicenseState copyWith({
    String? offlineToken,
    DateTime? trustedHighWater,
  }) {
    return StoredLicenseState(
      licenseKey: licenseKey,
      licenseId: licenseId,
      applicationId: applicationId,
      deviceId: deviceId,
      offlineToken: offlineToken ?? this.offlineToken,
      licenseType: licenseType,
      licenseExpiresAt: licenseExpiresAt,
      maxDevices: maxDevices,
      deviceName: deviceName,
      deviceActivatedAt: deviceActivatedAt,
      deviceLastSeenAt: deviceLastSeenAt,
      serverTimeAtSync: serverTimeAtSync,
      wallClockAtSync: wallClockAtSync,
      trustedHighWater: trustedHighWater ?? this.trustedHighWater,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'licenseKey': licenseKey,
    'licenseId': licenseId,
    'applicationId': applicationId,
    'deviceId': deviceId,
    'offlineToken': offlineToken,
    'licenseType': licenseType,
    'licenseExpiresAt': licenseExpiresAt?.toUtc().toIso8601String(),
    'maxDevices': maxDevices,
    'deviceName': deviceName,
    'deviceActivatedAt': deviceActivatedAt?.toUtc().toIso8601String(),
    'deviceLastSeenAt': deviceLastSeenAt?.toUtc().toIso8601String(),
    'serverTimeAtSync': serverTimeAtSync.toUtc().toIso8601String(),
    'wallClockAtSync': wallClockAtSync.toUtc().toIso8601String(),
    'trustedHighWater': trustedHighWater.toUtc().toIso8601String(),
  };

  factory StoredLicenseState.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported local license schema');
    }
    final offlineToken = json['offlineToken'];
    if (offlineToken != null && offlineToken is! String) {
      throw const FormatException('Invalid offline token');
    }
    return StoredLicenseState(
      licenseKey: _text(json['licenseKey'], 'licenseKey'),
      licenseId: _text(json['licenseId'], 'licenseId'),
      applicationId: _text(json['applicationId'], 'applicationId'),
      deviceId: _text(json['deviceId'], 'deviceId'),
      offlineToken: offlineToken as String?,
      licenseType: _optionalText(json['licenseType'], 'licenseType'),
      licenseExpiresAt: _optionalDate(json['licenseExpiresAt'], 'licenseExpiresAt'),
      maxDevices: _optionalPositiveInt(json['maxDevices'], 'maxDevices'),
      deviceName: _optionalText(json['deviceName'], 'deviceName'),
      deviceActivatedAt: _optionalDate(json['deviceActivatedAt'], 'deviceActivatedAt'),
      deviceLastSeenAt: _optionalDate(json['deviceLastSeenAt'], 'deviceLastSeenAt'),
      serverTimeAtSync: _date(json['serverTimeAtSync'], 'serverTimeAtSync'),
      wallClockAtSync: _date(json['wallClockAtSync'], 'wallClockAtSync'),
      trustedHighWater: _date(json['trustedHighWater'], 'trustedHighWater'),
    );
  }
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw FormatException('$field must be an object');
}

String _text(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value.trim();
}

String? _optionalText(Object? value, String field) {
  if (value == null) return null;
  return _text(value, field);
}

DateTime _date(Object? value, String field) {
  final text = _text(value, field);
  final parsed = DateTime.tryParse(text);
  if (parsed == null) {
    throw FormatException('$field must be an ISO-8601 timestamp');
  }
  return parsed.toUtc();
}

DateTime? _optionalDate(Object? value, String field) {
  if (value == null) return null;
  return _date(value, field);
}

int? _optionalPositiveInt(Object? value, String field) {
  if (value == null) return null;
  if (value is! int || value <= 0) {
    throw FormatException('$field must be a positive integer');
  }
  return value;
}
