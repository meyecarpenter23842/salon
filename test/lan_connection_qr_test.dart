import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_connection_qr.dart';
import 'package:salonmanager/core/lan/lan_health_client.dart';
void main() {
  test('QR roundtrip contains only LAN discovery, rejects credentials and unsafe destinations', () {
    for (final host in ['10.0.0.7', '172.16.1.8', '192.168.1.20']) {
      final connection = LanConnection('https://$host:8743/api/staff/v1', 'b' * 64);
      final raw = LanConnectionQr.encode(connection), decoded = LanConnectionQr.decode(raw);
      expect(decoded.apiUrl, connection.apiUrl); expect(decoded.certificateSha256, connection.certificateSha256);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      expect(data.keys.toSet(), {'kind', 'version', 'url', 'pin'});
      for (final mutation in [
        {...data, 'token': 'secret'}, {...data, 'code': '123456'}, {...data, 'version': 2},
        {...data, 'kind': 'other'}, {...data, 'pin': 'wrong'},
        ...['http://192.168.1.20/api/staff/v1', 'https://127.0.0.1/api/staff/v1',
          'https://8.8.8.8/api/staff/v1', 'https://salon.example/api/staff/v1',
          'https://user:secret@192.168.1.20/api/staff/v1',
          'https://192.168.1.20/api/staff/v1?token=secret'].map((url) => {...data, 'url': url}),
      ]) { expect(() => LanConnectionQr.decode(jsonEncode(mutation)), throwsFormatException); }
    }
    expect(() => LanConnectionQr.decode('x' * 1025), throwsFormatException);
    expect(() => LanConnectionQr.decode('[]'), throwsFormatException);
  });
}
