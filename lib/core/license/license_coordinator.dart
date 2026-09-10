import 'license_api.dart';
import 'license_config.dart';
import 'license_models.dart';
import 'license_storage.dart';
import 'offline_license_verifier.dart';

abstract interface class LicenseGateController {
  Future<LicenseGateResult> check();

  Future<LicenseGateResult> activate(String licenseKey);
}

class LicenseCoordinator implements LicenseGateController {
  LicenseCoordinator({
    required LicenseApi api,
    required LicenseStorage storage,
    required OfflineLicenseVerifier offlineVerifier,
    required LicenseRuntimeContext runtime,
    DateTime Function()? wallClock,
  }) : _api = api,
       _storage = storage,
       _offlineVerifier = offlineVerifier,
       _runtime = runtime,
       _wallClock = wallClock ?? (() => DateTime.now().toUtc());

  final LicenseApi _api;
  final LicenseStorage _storage;
  final OfflineLicenseVerifier _offlineVerifier;
  final LicenseRuntimeContext _runtime;
  final DateTime Function() _wallClock;

  @override
  Future<LicenseGateResult> check() async {
    StoredLicenseState? state;
    try {
      state = await _storage.readLicense();
    } catch (_) {
      return const LicenseGateResult(
        status: LicenseAccessStatus.blocked,
        message:
            'Dữ liệu kích hoạt cục bộ bị lỗi hoặc không thể đọc. Hãy nhập lại key để kích hoạt.',
      );
    }

    if (state == null) {
      return const LicenseGateResult(
        status: LicenseAccessStatus.activationRequired,
      );
    }
    if (state.deviceId != _runtime.deviceId) {
      return const LicenseGateResult(
        status: LicenseAccessStatus.blocked,
        message:
            'Thông tin thiết bị không khớp với lần kích hoạt trước. Hãy kích hoạt lại license.',
      );
    }

    try {
      final snapshot = await _api.validate(
        appCode: LicenseConfig.appCode,
        licenseKey: state.licenseKey,
        runtime: _runtime,
      );
      return await _acceptOnline(snapshot, state.licenseKey, previous: state);
    } on LicenseApiException catch (error) {
      return _blockedFromApi(error);
    } on LicenseNetworkException {
      return _tryOffline(state);
    }
  }

  @override
  Future<LicenseGateResult> activate(String licenseKey) async {
    final normalizedKey = licenseKey.trim();
    if (normalizedKey.isEmpty) {
      return const LicenseGateResult(
        status: LicenseAccessStatus.activationRequired,
        message: 'Anh nhập license key để kích hoạt Salon.',
      );
    }

    try {
      final snapshot = await _api.activate(
        appCode: LicenseConfig.appCode,
        licenseKey: normalizedKey,
        runtime: _runtime,
      );
      return await _acceptOnline(snapshot, normalizedKey);
    } on LicenseApiException catch (error) {
      return _blockedFromApi(error);
    } on LicenseNetworkException catch (error) {
      return LicenseGateResult(
        status: LicenseAccessStatus.blocked,
        message:
            '${error.message} Cần có mạng trong lần kích hoạt đầu tiên.',
      );
    }
  }

  Future<LicenseGateResult> _acceptOnline(
    LicenseServerSnapshot snapshot,
    String licenseKey, {
    StoredLicenseState? previous,
  }) async {
    if (snapshot.status != 'ACTIVE' || snapshot.deviceStatus != 'ACTIVE') {
      return const LicenseGateResult(
        status: LicenseAccessStatus.blocked,
        message: 'Key Manager không xác nhận license ở trạng thái hoạt động.',
      );
    }
    if (snapshot.appCode != LicenseConfig.appCode) {
      return const LicenseGateResult(
        status: LicenseAccessStatus.blocked,
        message: 'License được trả về không thuộc ứng dụng Salon.',
      );
    }
    if (snapshot.deviceId != _runtime.deviceId) {
      return const LicenseGateResult(
        status: LicenseAccessStatus.blocked,
        message: 'License được trả về không khớp thiết bị hiện tại.',
      );
    }

    final wallNow = _wallClock().toUtc();
    var highWater = snapshot.serverTime;
    final previousHighWater = previous?.trustedHighWater;
    if (previousHighWater != null && previousHighWater.isAfter(highWater)) {
      highWater = previousHighWater;
    }
    final state = StoredLicenseState(
      licenseKey: licenseKey,
      licenseId: snapshot.licenseId,
      applicationId: snapshot.applicationId,
      deviceId: _runtime.deviceId,
      offlineToken: snapshot.offline?.token,
      serverTimeAtSync: snapshot.serverTime,
      wallClockAtSync: wallNow,
      trustedHighWater: highWater,
    );

    try {
      await _storage.writeLicense(state);
    } catch (_) {
      return const LicenseGateResult(
        status: LicenseAccessStatus.blocked,
        message:
            'License hợp lệ nhưng không thể lưu trạng thái kích hoạt an toàn trên Windows.',
      );
    }

    return LicenseGateResult(
      status: LicenseAccessStatus.allowedOnline,
      requestId: snapshot.requestId,
    );
  }

  Future<LicenseGateResult> _tryOffline(StoredLicenseState state) async {
    final check = await _offlineVerifier.verify(
      state: state,
      wallClockNow: _wallClock().toUtc(),
    );
    if (!check.allowed) {
      return LicenseGateResult(
        status: LicenseAccessStatus.blocked,
        message:
            check.message ??
            'Không thể xác minh license khi offline. Hãy kết nối mạng và thử lại.',
      );
    }

    final highWater = check.trustedHighWater;
    if (highWater == null) {
      return const LicenseGateResult(
        status: LicenseAccessStatus.blocked,
        message: 'Trạng thái thời gian offline không hợp lệ.',
      );
    }

    try {
      await _storage.writeLicense(
        state.copyWith(trustedHighWater: highWater),
      );
    } catch (_) {
      return const LicenseGateResult(
        status: LicenseAccessStatus.blocked,
        message:
            'Không thể cập nhật trạng thái thời gian license offline an toàn.',
      );
    }

    return LicenseGateResult(
      status: LicenseAccessStatus.allowedOffline,
      message: 'Đang dùng quyền offline đã được Key Manager ký.',
      offlineRemaining: check.remaining,
    );
  }

  LicenseGateResult _blockedFromApi(LicenseApiException error) {
    final message = switch (error.code) {
      'INVALID_LICENSE' => 'License key không hợp lệ hoặc không còn hoạt động trên máy này.',
      'WRONG_APPLICATION' => 'License key này không được cấp cho Salon.',
      'APPLICATION_DISABLED' => 'Ứng dụng Salon đang bị vô hiệu hóa trên Key Manager.',
      'LICENSE_EXPIRED' => 'License key đã hết hạn.',
      'LICENSE_REVOKED' => 'License key đã bị thu hồi.',
      'DEVICE_REVOKED' => 'Thiết bị này đã bị thu hồi quyền sử dụng license.',
      'DEVICE_LIMIT_REACHED' => 'License key đã đạt giới hạn số thiết bị.',
      'UPDATE_REQUIRED' => 'Phiên bản Salon hiện tại quá cũ. Cần cập nhật Salon trước khi tiếp tục.',
      'RATE_LIMITED' => 'Key Manager đang giới hạn yêu cầu. Hãy thử lại sau.',
      'INVALID_REQUEST' => 'Salon gửi yêu cầu license không hợp lệ.',
      _ => error.message,
    };
    return LicenseGateResult(
      status: LicenseAccessStatus.blocked,
      message: message,
      requestId: error.requestId,
    );
  }
}
