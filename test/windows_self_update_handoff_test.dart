import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/services/windows_self_update_handoff.dart';

void main() {
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
