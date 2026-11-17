import 'dart:convert';
import 'dart:io';

import 'package:powwot/src/app_version.dart';
import 'package:powwot/src/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final apkBytes = utf8.encode('pretend this is an apk' * 100);
  final apkSha = UpdateService.sha256Hex(apkBytes);
  late Directory tmp;

  Map<String, dynamic> versionJson({int code = 3, String? sha}) => {
    'versionName': '0.1.2',
    'versionCode': code,
    'apkUrl': 'https://powwot.dorkforce.com/download/app.apk',
    'sha256': sha ?? apkSha,
    'notes': 'Chime',
    'minSupported': 0,
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('powwot_update_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  UpdateService service({
    required MockClient client,
    int installed = 2,
    bool Function()? hasPermission,
    bool Function()? requestPermission,
    List<String>? opened,
    ResultType result = ResultType.done,
    DateTime Function()? now,
  }) => UpdateService(
    client: client,
    installedBuild: () async => installed,
    cacheDir: () async => tmp,
    hasInstallPermission: () async => hasPermission?.call() ?? true,
    requestInstallPermission: () async => requestPermission?.call() ?? true,
    openInstaller: (path) async {
      opened?.add(path);
      return OpenResult(type: result);
    },
    now: now,
    supported: true,
  );

  MockClient versionClient(Object body, {int status = 200}) =>
      MockClient((_) async => http.Response(jsonEncode(body), status));

  group('checkForUpdate', () {
    test('offers a newer build', () async {
      final info = await service(client: versionClient(versionJson(code: 3)))
          .checkForUpdate();
      expect(info, isNotNull);
      expect(info!.versionCode, 3);
    });

    test('same or older build is not an update', () async {
      expect(
        await service(client: versionClient(versionJson(code: 2)))
            .checkForUpdate(),
        isNull,
      );
      expect(
        await service(client: versionClient(versionJson(code: 1)))
            .checkForUpdate(),
        isNull,
      );
    });

    test('server errors and junk are not an update', () async {
      expect(
        await service(client: versionClient({}, status: 404)).checkForUpdate(),
        isNull,
      );
      expect(
        await service(client: versionClient({'x': 1})).checkForUpdate(),
        isNull,
      );
      expect(
        await service(
          client: MockClient((_) async => throw http.ClientException('down')),
        ).checkForUpdate(),
        isNull,
      );
    });

    test(
      'the automatic check runs at most once a day, manual always',
      () async {
        var calls = 0;
        var clock = DateTime(2026, 11, 17, 9);
        final s = service(
          client: MockClient((_) async {
            calls++;
            return http.Response(jsonEncode(versionJson()), 200);
          }),
          now: () => clock,
        );
        expect(await s.checkForUpdate(), isNotNull);
        expect(calls, 1);
        clock = clock.add(const Duration(hours: 2));
        expect(await s.checkForUpdate(), isNull);
        expect(calls, 1);
        expect(await s.checkForUpdate(manual: true), isNotNull);
        expect(calls, 2);
        clock = clock.add(const Duration(hours: 25));
        expect(await s.checkForUpdate(), isNotNull);
        expect(calls, 3);
      },
    );

    test(
      '"Later" silences the automatic prompt for that release only',
      () async {
        var clock = DateTime(2026, 11, 17, 9);
        final s = service(
          client: versionClient(versionJson(code: 3)),
          now: () => clock,
        );
        final info = (await s.checkForUpdate())!;
        await s.postpone(info);
        clock = clock.add(const Duration(days: 2));
        expect(await s.checkForUpdate(), isNull);
        expect(await s.checkForUpdate(manual: true), isNotNull);

        final newer = service(
          client: versionClient(versionJson(code: 4)),
          now: () => clock,
        );
        clock = clock.add(const Duration(days: 2));
        expect((await newer.checkForUpdate())!.versionCode, 4);
      },
    );

    test('does nothing where self-update is unsupported', () async {
      var calls = 0;
      final s = UpdateService(
        supported: false,
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      expect(await s.checkForUpdate(manual: true), isNull);
      expect(calls, 0);
    });
  });

  group('downloadAndVerify', () {
    AppVersionInfo info({String? sha}) =>
        AppVersionInfo.tryParse(versionJson(sha: sha))!;

    MockClient apkClient({int status = 200, List<int>? bytes}) =>
        MockClient.streaming(
          (request, _) async => http.StreamedResponse(
            Stream.fromIterable([
              for (var i = 0; i < (bytes ?? apkBytes).length; i += 500)
                (bytes ?? apkBytes).sublist(
                  i,
                  (i + 500).clamp(0, (bytes ?? apkBytes).length),
                ),
            ]),
            status,
            contentLength: (bytes ?? apkBytes).length,
          ),
        );

    test(
      'saves the file when the checksum matches and reports progress',
      () async {
        final progress = <double>[];
        final file = await service(client: apkClient())
            .downloadAndVerify(info(), onProgress: progress.add);
        expect(await file.readAsBytes(), apkBytes);
        expect(progress.last, 1.0);
        expect(progress, orderedEquals([...progress]..sort()));
      },
    );

    test('a checksum mismatch deletes the file and throws', () async {
      final s = service(client: apkClient());
      await expectLater(
        s.downloadAndVerify(info(sha: 'b' * 64)),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.checksum,
          ),
        ),
      );
      expect(tmp.listSync(), isEmpty);
    });

    test('a corrupted download is caught', () async {
      final corrupted = [...apkBytes]..[10] ^= 0xFF;
      await expectLater(
        service(client: apkClient(bytes: corrupted)).downloadAndVerify(info()),
        throwsA(isA<UpdateException>()),
      );
      expect(tmp.listSync(), isEmpty);
    });

    test('an HTTP error is a network failure', () async {
      await expectLater(
        service(client: apkClient(status: 404)).downloadAndVerify(info()),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.network,
          ),
        ),
      );
    });
  });

  group('install', () {
    final fake = File('/tmp/none.apk');
    final dummy = MockClient((_) async => http.Response('', 200));

    test('opens the installer when install permission is granted', () async {
      final opened = <String>[];
      await service(client: dummy, opened: opened).install(fake);
      expect(opened, [fake.path]);
    });

    test('asks for the permission first, then installs', () async {
      var granted = false;
      var asked = 0;
      final opened = <String>[];
      await service(
        client: dummy,
        opened: opened,
        hasPermission: () => granted,
        requestPermission: () {
          asked++;
          granted = true;
          return true;
        },
      ).install(fake);
      expect(asked, 1);
      expect(opened, hasLength(1));
    });

    test('does not open the installer when permission is refused', () async {
      final opened = <String>[];
      await expectLater(
        service(
          client: dummy,
          opened: opened,
          hasPermission: () => false,
          requestPermission: () => false,
        ).install(fake),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.installPermission,
          ),
        ),
      );
      expect(opened, isEmpty);
    });

    test('an installer that will not open is an error', () async {
      await expectLater(
        service(client: dummy, result: ResultType.noAppToOpen).install(fake),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.installer,
          ),
        ),
      );
    });
  });

  test('cleanUp removes leftover update files only', () async {
    await File('${tmp.path}/powwot-update-3.apk').writeAsBytes([1]);
    await File('${tmp.path}/keep.txt').writeAsBytes([1]);
    await service(client: MockClient((_) async => http.Response('', 200)))
        .cleanUp();
    expect(tmp.listSync().map((e) => e.uri.pathSegments.last), ['keep.txt']);
  });
}
