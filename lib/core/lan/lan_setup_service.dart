import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:basic_utils/basic_utils.dart';
import 'package:uuid/uuid.dart';

import 'lan_health_host.dart';

class LanNetwork {
  const LanNetwork(this.name, this.address);
  final String name;
  final InternetAddress address;
}

bool isPrivateLanAddress(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4 || address.isLoopback) return false;
  final b = address.rawAddress;
  return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
}

Future<List<LanNetwork>> listLanNetworks() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4, includeLoopback: false,
  );
  final found = <String, LanNetwork>{};
  for (final network in interfaces) {
    for (final address in network.addresses.where(isPrivateLanAddress)) {
      found[address.address] = LanNetwork(network.name, address);
    }
  }
  return found.values.toList();
}

Directory desktopLanDirectory() {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) throw StateError('Missing app data');
  return Directory('$appData/HairSpaManager/lan');
}

Map<String, String> _newIdentity() {
  final keys = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final privateKey = keys.privateKey as RSAPrivateKey;
  final publicKey = keys.publicKey as RSAPublicKey;
  final csr = X509Utils.generateRsaCsrPem(
    {'CN': 'Salon Desktop'}, privateKey, publicKey,
  );
  final random = Random.secure();
  final serial = List.generate(16, (_) => random.nextInt(256));
  serial[0] = (serial[0] & 0x7f) | 1;
  final serialNumber = BigInt.parse(
    serial.map((b) => b.toRadixString(16).padLeft(2, '0')).join(), radix: 16,
  ).toString();
  return {
    'certificate': X509Utils.generateSelfSignedCertificate(
      privateKey, csr, 365, cA: false,
      extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH],
      serialNumber: serialNumber,
      notBefore: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    ),
    'key': CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
  };
}

/// Persists machine-only TLS identity. No DB, license or firewall mutations.
class LanSetupService {
  const LanSetupService(this.directory);
  final Directory directory;
  static final Set<String> _ownedPaths = {};

  Future<LanHostConfig?> load() async {
    final file = File('${directory.path}/config.json');
    if (!await file.exists()) return null;
    return LanHostConfig.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  }

  Future<void> _restrict(Directory identity) async {
    if (Platform.isWindows) {
      final user = Platform.environment['USERNAME'];
      final domain = Platform.environment['USERDOMAIN'];
      if (user == null || user.isEmpty || domain == null || domain.isEmpty) {
        throw StateError('Cannot identify current Windows account');
      }
      final result = await Process.run('icacls.exe', [
        identity.path, '/inheritance:r', '/grant:r', '$domain\\$user:(OI)(CI)F',
      ]);
      if (result.exitCode != 0) throw StateError('Cannot protect TLS identity');
    } else {
      final result = await Process.run('chmod', ['700', identity.path]);
      if (result.exitCode != 0) throw StateError('Cannot protect TLS identity');
    }
  }

  Future<LanHostConfig> prepare(InternetAddress address) async {
    // The host validates IP/port, including rejecting public/wildcard endpoints.
    LanHostConfig(address: address, port: 8743,
      certificatePath: '', privateKeyPath: '');
    await directory.create(recursive: true);
    final lockFile = File('${directory.path}/setup.lock');
    final lockPath = lockFile.absolute.path;
    if (!_ownedPaths.add(lockPath)) throw StateError('Setup already running');
    RandomAccessFile? lock;
    Directory? createdIdentity;
    File? pending;
    var committed = false;
    try {
      lock = await lockFile.open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive, 0, 1);
      final existing = await load();
      LanHostConfig config;
      if (existing != null) {
        // A network/IP change retains the phone's trusted certificate identity.
        config = LanHostConfig(address: address, port: existing.port,
          certificatePath: existing.certificatePath, privateKeyPath: existing.privateKeyPath);
      } else {
        createdIdentity = await Directory('${directory.path}/identity-${const Uuid().v4()}')
          .create();
        await _restrict(createdIdentity);
        final identity = await Isolate.run(_newIdentity);
        final cert = File('${createdIdentity.path}/certificate.pem');
        final key = File('${createdIdentity.path}/private-key.pem');
        await cert.writeAsString(identity['certificate']!, flush: true);
        await key.writeAsString(identity['key']!, flush: true);
        config = LanHostConfig(address: address, port: 8743,
          certificatePath: cert.path, privateKeyPath: key.path);
      }
      // Validate real PEM/key loading before making configuration discoverable.
      await config.securityContext();
      pending = File('${directory.path}/config-${const Uuid().v4()}.tmp');
      await pending.writeAsString(jsonEncode({
        'address': config.address.address, 'port': config.port,
        'certificatePath': config.certificatePath, 'privateKeyPath': config.privateKeyPath,
      }), flush: true);
      await pending.rename('${directory.path}/config.json');
      committed = true;
      return config;
    } finally {
      await lock?.close();
      _ownedPaths.remove(lockPath);
      if (pending != null && await pending.exists()) await pending.delete();
      if (!committed && createdIdentity != null && await createdIdentity.exists()) {
        await createdIdentity.delete(recursive: true);
      }
    }
  }
}
