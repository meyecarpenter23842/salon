import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_health_host.dart';

void main() {
  test('configuration rejects public/wildcard endpoints and invalid ports', () {
    for (final address in ['0.0.0.0', '8.8.8.8', '::1']) {
      expect(
        () => LanHostConfig(
          address: InternetAddress(address), port: 8743,
          certificatePath: '', privateKeyPath: '',
        ),
        throwsFormatException,
      );
    }
    expect(() => LanHostConfig.fromJson({}), throwsFormatException);
  });

  final fixture = Platform.environment['SALON_TEST_TLS_DIR'];
  if (fixture == null) {
    test('TLS integration requires generated CI certificate fixture', () {},
      skip: 'Set SALON_TEST_TLS_DIR to generated PEM fixture directory.');
    return;
  }

  late Directory root;
  late LanHealthHost host;
  late HttpClient client;
  late LanHostConfig config;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('salon-health-test-');
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    config = LanHostConfig(
      address: InternetAddress.loopbackIPv4,
      port: port,
      certificatePath: '$fixture/certificate.pem',
      privateKeyPath: '$fixture/private-key.pem',
    );
    host = LanHealthHost(lockFile: File('${root.path}/backend.lock'));
    final trust = SecurityContext(withTrustedRoots: false);
    trust.setTrustedCertificatesBytes(
      await File(config.certificatePath).readAsBytes(),
    );
    client = HttpClient(context: trust);
    client.connectionTimeout = const Duration(seconds: 3);
  });

  tearDown(() async {
    client.close(force: true);
    await host.stop();
    await root.delete(recursive: true);
  });

  Future<HttpClientResponse> request(String method, String suffix) async {
    final url = Uri.parse('${config.apiUrl}$suffix');
    return (await client.openUrl(method, url)).close();
  }

  test('HTTPS health responds without database; unsupported routes refuse', () async {
    await host.start(config);
    final response = await request('GET', '/health');
    expect(response.statusCode, 200);
    expect(response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
    expect(jsonDecode(await utf8.decoder.bind(response).join()),
      {'apiVersion': 1, 'status': 'ok'});
    for (final entry in [
      ['POST', '/health', 400],
      ['GET', '/health?secret=x', 400],
      ['POST', '/billing-sessions/bill/checkout', 404],
      ['GET', '/customers', 404],
    ]) {
      final rejected = await request(entry[0] as String, entry[1] as String);
      expect(rejected.statusCode, entry[2]);
      final body = await utf8.decoder.bind(rejected).join();
      expect(body, isNot(contains(fixture)));
      expect(jsonDecode(body)['error']['code'],
        entry[2] == 400 ? 'invalid_request' : 'not_found');
    }
    final untrusted = HttpClient(context: SecurityContext(withTrustedRoots: false));
    untrusted.connectionTimeout = const Duration(seconds: 3);
    try {
      await expectLater(
        () async => (await untrusted.getUrl(
          Uri.parse('${config.apiUrl}/health'),
        )).close(),
        throwsA(isA<HandshakeException>()),
      );
    } finally {
      untrusted.close(force: true);
    }
  });

  test('second owner refused; stop releases port and lock for restart', () async {
    await host.start(config);
    final other = LanHealthHost(lockFile: File('${root.path}/backend.lock'));
    await expectLater(other.start(config), throwsStateError);
    expect(host.running, isTrue);
    await other.stop();
    await host.stop();
    await other.start(config);
    expect(other.running, isTrue);
    await other.stop();
    await host.start(config);
  });

  test('OS lock excludes another process until host shuts down', () async {
    await host.start(config);
    Future<ProcessResult> probe() => Process.run(
      'dart', ['run', 'test/support/lan_lock_probe.dart', '${root.path}/backend.lock'],
      runInShell: Platform.isWindows,
    );
    final held = await probe();
    expect(held.exitCode, 23, reason: held.stderr.toString());
    await host.stop();
    final released = await probe();
    expect(released.exitCode, 0, reason: released.stderr.toString());
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('stop during startup cannot leave a listener or lock behind', () async {
    final starting = host.start(config);
    final stopping = host.stop();
    await starting;
    await stopping;
    expect(host.running, isFalse);
    await host.start(config);
    expect(host.running, isTrue);
  });

  test('bind failure releases owner; failed certificate never opens server', () async {
    final occupied = await ServerSocket.bind(config.address, config.port);
    await expectLater(host.start(config), throwsA(isA<SocketException>()));
    expect(host.running, isFalse);
    await occupied.close();
    await host.stop();
    await host.start(config);
    await host.stop();
    final broken = LanHostConfig(
      address: config.address, port: config.port,
      certificatePath: '${root.path}/missing.pem', privateKeyPath: '',
    );
    await expectLater(host.start(broken), throwsA(isA<FileSystemException>()));
    await host.stop();
    await host.start(config);
  });
}
