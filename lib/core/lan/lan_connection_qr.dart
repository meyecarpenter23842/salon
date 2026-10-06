import 'dart:convert';
import 'dart:io';
import 'lan_health_client.dart';
import 'lan_setup_service.dart';

/// Public connection discovery only. Never encode pairing codes or credentials.
class LanConnectionQr {
  static String encode(LanConnection connection) {
    _local(connection);
    return jsonEncode({'kind': 'salon-lan', 'version': 1,
      'url': connection.apiUrl.toString(), 'pin': connection.certificateSha256});
  }
  static LanConnection decode(String text) {
    if (utf8.encode(text).length > 1024) throw const FormatException('QR too large');
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic> || json.length != 4 || json['kind'] != 'salon-lan' ||
        json['version'] != 1 || json['url'] is! String || json['pin'] is! String) {
      throw const FormatException('Unsupported salon QR');
    }
    final connection = LanConnection(json['url'] as String, json['pin'] as String);
    _local(connection); return connection;
  }
  static void _local(LanConnection connection) {
    final address = InternetAddress.tryParse(connection.apiUrl.host);
    if (address == null || !isPrivateLanAddress(address)) throw const FormatException('QR must use a private LAN IPv4 address');
  }
}
