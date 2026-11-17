/// What `version.json` on the download page says is the latest build.
///
/// ```json
/// { "versionName": "0.1.2", "versionCode": 3,
///   "apkUrl": "https://powwot.dorkforce.com/download/Powwot-0.1.2-3.apk",
///   "sha256": "<64 hex chars>", "notes": "What changed.", "minSupported": 1 }
/// ```
class AppVersionInfo {
  final String versionName;
  final int versionCode;
  final Uri apkUrl;
  final String sha256;
  final String notes;

  /// Builds older than this must update (the dialog cannot be dismissed).
  final int minSupported;

  const AppVersionInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256,
    this.notes = '',
    this.minSupported = 0,
  });

  /// Parses a decoded version.json, or returns null if it is missing a field
  /// or unsafe (the APK link must be HTTPS and the checksum 64 hex digits).
  static AppVersionInfo? tryParse(Object? json) {
    if (json is! Map) return null;
    final code = _asInt(json['versionCode']);
    final url = json['apkUrl'];
    final sha = json['sha256'];
    if (code == null || code <= 0) return null;
    if (url is! String || sha is! String) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    final digest = sha.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) return null;
    final name = json['versionName'];
    final notes = json['notes'];
    return AppVersionInfo(
      versionName: name is String && name.isNotEmpty ? name : '$code',
      versionCode: code,
      apkUrl: uri,
      sha256: digest,
      notes: notes is String ? notes.trim() : '',
      minSupported: _asInt(json['minSupported']) ?? 0,
    );
  }

  /// True when this release is newer than the installed [buildNumber].
  bool isNewerThan(int buildNumber) => versionCode > buildNumber;

  /// True when the installed [buildNumber] is too old to keep using.
  bool isRequiredFor(int buildNumber) => buildNumber < minSupported;

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}
