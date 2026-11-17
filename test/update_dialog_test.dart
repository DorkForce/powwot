import 'dart:convert';
import 'dart:io';

import 'package:powwot/src/app_version.dart';
import 'package:powwot/src/update_service.dart';
import 'package:powwot/src/ui/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final apk = utf8.encode('apk bytes');
  final goodSha = UpdateService.sha256Hex(apk);

  AppVersionInfo info({String? sha, int minSupported = 0}) =>
      AppVersionInfo.tryParse({
        'versionName': '0.1.2',
        'versionCode': 4,
        'apkUrl': 'https://powwot.dorkforce.com/download/app.apk',
        'sha256': sha ?? goodSha,
        'notes': 'Custom chime and invites',
        'minSupported': minSupported,
      })!;

  UpdateService service(List<String> opened, Directory dir) => UpdateService(
    client: MockClient.streaming(
      (request, _) async => http.StreamedResponse(
        Stream.value(apk),
        200,
        contentLength: apk.length,
      ),
    ),
    installedBuild: () async => 3,
    cacheDir: () async => dir,
    hasInstallPermission: () async => true,
    requestInstallPermission: () async => true,
    openInstaller: (path) async {
      opened.add(path);
      return OpenResult();
    },
    supported: true,
  );

  Future<void> open(
    WidgetTester tester,
    UpdateService s,
    AppVersionInfo i, {
    bool required = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showUpdateDialog(context, s, i, required: required),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the version and notes with Later and Update', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('powwot_ud_');
    addTearDown(() => dir.deleteSync(recursive: true));
    await open(tester, service([], dir), info());
    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('0.1.2'), findsOneWidget);
    expect(find.text('Custom chime and invites'), findsOneWidget);
    expect(find.byKey(const Key('update_later')), findsOneWidget);
    expect(find.byKey(const Key('update_now')), findsOneWidget);
  });

  testWidgets('a required update has no Later button', (tester) async {
    final dir = Directory.systemTemp.createTempSync('powwot_ud_');
    addTearDown(() => dir.deleteSync(recursive: true));
    await open(tester, service([], dir), info(minSupported: 4), required: true);
    expect(find.byKey(const Key('update_later')), findsNothing);
    expect(find.textContaining('required'), findsOneWidget);
  });

  testWidgets('a checksum mismatch shows an error and never installs', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('powwot_ud_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final opened = <String>[];
    await open(tester, service(opened, dir), info(sha: 'c' * 64));
    await tester.tap(find.byKey(const Key('update_now')));
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byKey(const Key('update_error')).evaluate().isNotEmpty) break;
    }
    expect(find.byKey(const Key('update_error')), findsOneWidget);
    expect(find.textContaining('checksum'), findsOneWidget);
    expect(opened, isEmpty);
  });
}
