import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'license_models.dart';

abstract interface class LicenseApi {
  Future<LicenseServerSnapshot> activate({
    required String appCode,
    required String licenseKey,
    required LicenseRuntimeContext runtime,
  });

  Future<LicenseServerSnapshot> validate({
    required String appCode,
    required String licenseKey,
    required LicenseRuntimeContext runtime,
  });
}

class LicenseApiException implements Exception {
  const LicenseApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.requestId,
  });

  final int statusCode;
  final String code;
  final String message;
  final String? requestId;

  @override
  String toString() => '$code ($statusCode): $message';
}

class LicenseNetworkException implements Exception {
  const LicenseNetworkException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class HttpLicenseApi implements LicenseApi {
  HttpLicenseApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<LicenseServerSnapshot> activate({
    required String appCode,
    required String licenseKey,
    required LicenseRuntimeContext runtime,
  }) {
    return _post(
      '/api/v1/license/activate',
      {
        'appCode': appCode,
        'licenseKey': licenseKey,
        'deviceId': runtime.deviceId,
        'deviceName': runtime.deviceName,
        'os': runtime.os,
        'appVersion': runtime.appVersion,
      },
    );
  }

  @override
  Future<LicenseServerSnapshot> validate({
    required String appCode,
    required String licenseKey,
    required LicenseRuntimeContext runtime,
  }) {
    return _post(
      '/api/v1/license/validate',
      {
        'appCode': appCode,
        'licenseKey': licenseKey,
        'deviceId': runtime.deviceId,
        'appVersion': runtime.appVersion,
      },
    );
  }

  Future<LicenseServerSnapshot> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final response = await _client
          .post(
            uri,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(timeout);

      Map<String, dynamic> body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          throw const FormatException('Response must be a JSON object');
        }
        body = Map<String, dynamic>.from(decoded);
      } on FormatException catch (error) {
        throw LicenseNetworkException(
          'Key Manager trả về dữ liệu không hợp lệ.',
          error,
        );
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          return LicenseServerSnapshot.fromJson(body);
        } on FormatException catch (error) {
          throw LicenseNetworkException(
            'Key Manager trả về dữ liệu license không hợp lệ.',
            error,
          );
        }
      }

      final errorJson = body['error'];
      final error = errorJson is Map
          ? Map<String, dynamic>.from(errorJson)
          : const <String, dynamic>{};
      final code = (error['code'] as String?)?.trim();
      final message = (error['message'] as String?)?.trim();
      final requestId = (body['requestId'] as String?)?.trim();
      throw LicenseApiException(
        statusCode: response.statusCode,
        code: code?.isNotEmpty == true ? code! : 'LICENSE_API_ERROR',
        message: message?.isNotEmpty == true
            ? message!
            : 'Key Manager từ chối yêu cầu license.',
        requestId: requestId?.isNotEmpty == true ? requestId : null,
      );
    } on LicenseApiException {
      rethrow;
    } on LicenseNetworkException {
      rethrow;
    } on TimeoutException catch (error) {
      throw LicenseNetworkException('Kết nối Key Manager bị quá thời gian.', error);
    } on SocketException catch (error) {
      throw LicenseNetworkException('Không thể kết nối Key Manager.', error);
    } on http.ClientException catch (error) {
      throw LicenseNetworkException('Không thể kết nối Key Manager.', error);
    } on FormatException catch (error) {
      throw LicenseNetworkException('URL Key Manager không hợp lệ.', error);
    }
  }
}
