import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/services/windows_self_update_handoff.dart';

void main() {
  _windowsLaunchTests();
  test('self-update helper delays briefly, closes gracefully, installs, then restarts', () {
    expect(
      windowsSelfUpdateHelperScript,
      contains('Start-Sleep -Milliseconds 900'),
    );
    expect(windowsSelfUpdateHelperScript, contains('CloseMainWindow()'));
    expect(
      windowsSelfUpdateHelperScript,
      contains(r'-FilePath $Installer'),
    );
    expect(windowsSelfUpdateHelperScript, contains('-Wait'));
    expect(
      windowsSelfUpdateHelperScript,
      contains(
        r'Start-Process -FilePath $Executable -WorkingDirectory $InstallDir',
      ),
    );
  });

  test('self-update helper never waits on a parent PID or force-kills Salon', () {
    expect(windowsSelfUpdateHelperScript, isNot(contains('ParentPid')));
    expect(windowsSelfUpdateHelperScript, isNot(contains('Wait-ProcessExit')));
    expect(windowsSelfUpdateHelperScript.toLowerCase(), isNot(contains('taskkill')));
    expect(windowsSelfUpdateHelperScript, isNot(contains('/F')));
    expect(
      windowsSelfUpdateHelperScript,
      contains('aborting instead of force-killing'),
    );
  });

  test('self-update helper receives an explicit diagnostic log path', () {
    expect(windowsSelfUpdateHelperScript, contains(r'[string]$LogPath'));
    expect(windowsSelfUpdateHelperScript, contains(r'$logPath = $LogPath'));
  });

  test('self-update helper source is ASCII for Windows PowerShell 5.1', () {
    expect(
      windowsSelfUpdateHelperScript.codeUnits.every((unit) => unit <= 0x7f),
      isTrue,
    );
  });

  test('writeHelper emits the exact ASCII helper bytes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'salon-self-update-test-',
    );
    try {
      final helper = await const WindowsSelfUpdateHandoff().writeHelper(
        directory,
      );
      expect(
        await helper.readAsBytes(),
        ascii.encode(windowsSelfUpdateHelperScript),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

void _windowsLaunchTests() {
  if (!Platform.isWindows) return;

  const parameters = r"""
param(
  [string]$Installer, [string]$Executable, [string]$InstallDir,
  [string]$LogPath, [string]$ReadyPath, [string]$ContinuePath
)
""";

  test('normal hidden helper ACKs and survives Dart parent exit', () async {
    final directory = await Directory.systemTemp.createTemp('handoff-survival-');
    try {
      final helper = File('${directory.path}/probe.ps1');
      await helper.writeAsString(parameters + r"""
Set-Content -LiteralPath $ReadyPath -Encoding ASCII -Value $PID
$deadline = (Get-Date).AddSeconds(15)
while (-not (Test-Path -LiteralPath $ContinuePath)) {
  if ((Get-Date) -ge $deadline) { exit 24 }
  Start-Sleep -Milliseconds 50
}
Remove-Item -LiteralPath $ReadyPath, $ContinuePath -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Set-Content -LiteralPath $LogPath -Value 'survived_parent_exit'
""");
      final parent = await Process.run(
        'dart',
        ['run', 'test/support/updater_handoff_probe.dart', helper.path, directory.path],
        runInShell: true,
      );
      expect(parent.exitCode, 0, reason: parent.stderr.toString());
      expect(parent.stdout.toString(), contains('ready-helper-pid='));
      final log = File('${directory.path}/survived.log');
      final watch = Stopwatch()..start();
      while (!await log.exists() && watch.elapsed < const Duration(seconds: 10)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(await log.exists(), isTrue,
        reason: 'PowerShell must still run after the Dart parent has exited.');
      expect(await log.readAsString(), contains('survived_parent_exit'));
    } finally {
      await directory.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('helper early exit rejects handoff before app shutdown', () async {
    final directory = await Directory.systemTemp.createTemp('handoff-early-exit-');
    try {
      final helper = File('${directory.path}/probe.ps1');
      await helper.writeAsString(parameters + '\nexit 37\n');
      await expectLater(
        const WindowsSelfUpdateHandoff().launch(
          helper: helper, installer: File('unused-installer'),
          executable: 'unused-app', installDir: directory.path,
          logPath: '${directory.path}/unused.log',
        ),
        throwsStateError,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('missing ACK times out and stops only the newly created helper', () async {
    final directory = await Directory.systemTemp.createTemp('handoff-timeout-');
    try {
      final helper = File('${directory.path}/probe.ps1');
      await helper.writeAsString(parameters + r"""
Start-Sleep -Seconds 20
Set-Content -LiteralPath $LogPath -Value 'must_not_run'
""");
      final log = File('${directory.path}/unused.log');
      await expectLater(
        const WindowsSelfUpdateHandoff().launch(
          helper: helper, installer: File('unused-installer'),
          executable: 'unused-app', installDir: directory.path,
          logPath: log.path, readyTimeout: const Duration(milliseconds: 300),
        ),
        throwsStateError,
      );
      expect(await log.exists(), isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
