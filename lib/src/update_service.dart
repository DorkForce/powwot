import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_version.dart';

enum UpdateFailure {
  /// version.json or the APK could not be fetched.
  network,

  /// The downloaded file did not match the published SHA-256.
  checksum,

  /// The user has not allowed "install unknown apps" for Powwot.
  installPermission,

  /// The installer could not be opened.
  installer,
}

class UpdateException implements Exception {
  final UpdateFailure failure;
  const UpdateException(this.failure);

  String get message {
    switch (failure) {
      case UpdateFailure.network:
        return 'Could not download the update. Check your connection.';
      case UpdateFailure.checksum:
        return 'The download did not match its checksum, so it was not '
            'installed. Try again.';
      case UpdateFailure.installPermission:
        return 'Allow Powwot to install apps in Settings, then tap Update '
            'again.';
      case UpdateFailure.installer:
        return 'Could not open the installer.';
    }
  }

  @override
  String toString() => 'UpdateException($failure)';
}

/// Checks the download page for a newer build and installs it.
///
/// Flow: [checkForUpdate] reads `version.json`; [downloadAndVerify] streams
/// the APK to the cache and checks its SHA-256; [install] asks for the
/// "install unknown apps" permission if needed and opens Android's installer.
/// Only Android installs; elsewhere [isSupported] is false.
class UpdateService {
  static const String defaultVersionUrl =
      'https://powwot.dorkforce.com/download/version.json';
  static const String _lastCheckKey = 'update_last_check_ms';
  static const String _dismissedKey = 'update_dismissed_code';

  /// How often the automatic check runs (a manual check always runs).
  static const Duration checkInterval = Duration(hours: 24);

  final Uri versionUrl;
  final http.Client? _client;
  final Future<int> Function() _installedBuild;
  final Future<Directory> Function() _cacheDir;
  final Future<bool> Function() _hasInstallPermission;
  final Future<bool> Function() _requestInstallPermission;
  final Future<OpenResult> Function(String path) _openInstaller;
  final DateTime Function() _now;
  final bool? _supportedOverride;

  UpdateService({
    Uri? versionUrl,
    this._client,
    Future<int> Function()? installedBuild,
    Future<Directory> Function()? cacheDir,
    Future<bool> Function()? hasInstallPermission,
    Future<bool> Function()? requestInstallPermission,
    Future<OpenResult> Function(String path)? openInstaller,
    DateTime Function()? now,
    bool? supported,
  }) : versionUrl = versionUrl ?? Uri.parse(defaultVersionUrl),
       _installedBuild = installedBuild ?? _platformInstalledBuild,
       _cacheDir = cacheDir ?? getTemporaryDirectory,
       _hasInstallPermission =
           hasInstallPermission ??
           (() => Permission.requestInstallPackages.isGranted),
       _requestInstallPermission =
           requestInstallPermission ??
           (() async =>
               (await Permission.requestInstallPackages.request()).isGranted),
       _openInstaller =
           openInstaller ??
           ((path) => OpenFilex.open(
             path,
             type: 'application/vnd.android.package-archive',
           )),
       _now = now ?? DateTime.now,
       _supportedOverride = supported;

  /// Self-update only works on Android.
  bool get isSupported =>
      _supportedOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static Future<int> _platformInstalledBuild() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// The installed build number (Android versionCode).
  Future<int> installedBuild() => _installedBuild();

  /// Fetches version.json. Returns null if it cannot be read or is invalid.
  Future<AppVersionInfo?> fetchLatest() async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(versionUrl, headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      return AppVersionInfo.tryParse(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
    } catch (e) {
      debugPrint('Update check failed: $e');
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }

  /// The newer release to offer, or null.
  ///
  /// A manual check ([manual] true) always asks the server and ignores an
  /// earlier "Later". The automatic check runs at most once per
  /// [checkInterval], and stays quiet about a release the user already
  /// postponed unless it is required.
  Future<AppVersionInfo?> checkForUpdate({bool manual = false}) async {
    if (!isSupported) return null;
    final prefs = await SharedPreferences.getInstance();
    final nowMs = _now().millisecondsSinceEpoch;
    if (!manual) {
      final last = prefs.getInt(_lastCheckKey) ?? 0;
      if (nowMs - last < checkInterval.inMilliseconds && nowMs >= last) {
        return null;
      }
    }
    final latest = await fetchLatest();
    if (latest == null) return null;
    await prefs.setInt(_lastCheckKey, nowMs);
    final installed = await installedBuild();
    if (!latest.isNewerThan(installed)) return null;
    if (!manual &&
        !latest.isRequiredFor(installed) &&
        prefs.getInt(_dismissedKey) == latest.versionCode) {
      return null;
    }
    return latest;
  }

  /// Remembers that the user chose "Later" for [info].
  Future<void> postpone(AppVersionInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissedKey, info.versionCode);
  }

  /// SHA-256 of [bytes] as lowercase hex.
  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  /// Downloads the APK and checks its SHA-256 against [info]. Returns the
  /// file. A file that does not match is deleted and [UpdateException]
  /// (checksum) is thrown. [onProgress] gets 0..1 (null total => no calls).
  Future<File> downloadAndVerify(
    AppVersionInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/powwot-update-${info.versionCode}.apk');
    final client = _client ?? http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', info.apkUrl);
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const UpdateException(UpdateFailure.network);
      }
      if (await file.exists()) await file.delete();
      sink = file.openWrite();
      final total = response.contentLength ?? 0;
      var received = 0;
      final digestSink = _DigestCollector();
      final hasher = sha256.startChunkedConversion(digestSink);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
      hasher.close();
      await sink.flush();
      await sink.close();
      sink = null;
      if (digestSink.hex != info.sha256) {
        await file.delete();
        throw const UpdateException(UpdateFailure.checksum);
      }
      onProgress?.call(1);
      return file;
    } on UpdateException {
      rethrow;
    } catch (e) {
      debugPrint('Update download failed: $e');
      try {
        await sink?.close();
        if (await file.exists()) await file.delete();
      } catch (_) {}
      throw const UpdateException(UpdateFailure.network);
    } finally {
      if (_client == null) client.close();
    }
  }

  /// Opens Android's installer for a verified [apk]. Asks for the "install
  /// unknown apps" permission first (Android shows its own settings screen).
  Future<void> install(File apk) async {
    if (!await _hasInstallPermission()) {
      final granted = await _requestInstallPermission();
      if (!granted) {
        throw const UpdateException(UpdateFailure.installPermission);
      }
    }
    final result = await _openInstaller(apk.path);
    if (result.type != ResultType.done) {
      debugPrint('Installer did not open: ${result.type} ${result.message}');
      throw const UpdateException(UpdateFailure.installer);
    }
  }

  /// Deletes leftover update files from the cache.
  Future<void> cleanUp() async {
    try {
      final dir = await _cacheDir();
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        final name = entity.uri.pathSegments.last;
        if (entity is File &&
            name.startsWith('powwot-update-') &&
            name.endsWith('.apk')) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }
}

class _DigestCollector implements Sink<Digest> {
  String hex = '';

  @override
  void add(Digest data) => hex = data.toString();

  @override
  void close() {}
}
