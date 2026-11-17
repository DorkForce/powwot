import 'package:powwot/src/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sha = 'a' * 64;
  Map<String, dynamic> json({Object? code = 3, Object? url, Object? hash}) => {
    'versionName': '0.1.2',
    'versionCode': code,
    'apkUrl': url ?? 'https://powwot.dorkforce.com/download/Powwot-0.1.2-3.apk',
    'sha256': hash ?? sha,
    'notes': ' Self-hosted updates. ',
    'minSupported': 1,
  };

  group('AppVersionInfo.tryParse', () {
    test('parses a valid version.json', () {
      final info = AppVersionInfo.tryParse(json())!;
      expect(info.versionName, '0.1.2');
      expect(info.versionCode, 3);
      expect(info.apkUrl.host, 'powwot.dorkforce.com');
      expect(info.sha256, sha);
      expect(info.notes, 'Self-hosted updates.');
      expect(info.minSupported, 1);
    });

    test('accepts the code as a string and an uppercase checksum', () {
      final info = AppVersionInfo.tryParse(json(code: '7', hash: 'A' * 64))!;
      expect(info.versionCode, 7);
      expect(info.sha256, sha);
    });

    test('rejects missing or unsafe data', () {
      expect(AppVersionInfo.tryParse(null), isNull);
      expect(AppVersionInfo.tryParse('x'), isNull);
      expect(AppVersionInfo.tryParse(json(code: 0)), isNull);
      expect(AppVersionInfo.tryParse(json(code: 'abc')), isNull);
      expect(AppVersionInfo.tryParse(json(hash: 'abc123')), isNull);
      expect(
        AppVersionInfo.tryParse(json(url: 'http://powwot.dorkforce.com/a.apk')),
        isNull,
      );
      expect(AppVersionInfo.tryParse(json(url: 'not a url')), isNull);
      expect(AppVersionInfo.tryParse({'versionCode': 3}), isNull);
    });
  });

  group('version compare', () {
    final info = AppVersionInfo.tryParse(json())!;

    test('newer only when versionCode is greater than the installed build', () {
      expect(info.isNewerThan(2), isTrue);
      expect(info.isNewerThan(3), isFalse);
      expect(info.isNewerThan(4), isFalse);
    });

    test('required when the installed build is below minSupported', () {
      expect(info.isRequiredFor(0), isTrue);
      expect(info.isRequiredFor(1), isFalse);
      expect(info.isRequiredFor(3), isFalse);
    });

    test('no minimum means never required', () {
      final noMin = AppVersionInfo.tryParse(
        {...json()}..remove('minSupported'),
      )!;
      expect(noMin.minSupported, 0);
      expect(noMin.isRequiredFor(1), isFalse);
    });
  });
}
