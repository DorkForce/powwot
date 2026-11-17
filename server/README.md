# Powwot download page

Files under `public/download/` are served at https://powwot.dorkforce.com/download/.

- `index.html` — download page (navy and gold). Reads `version.json` for the latest build.
- `qr.svg` — static QR code for https://powwot.dorkforce.com/download/
- `version.json` — `{versionName, versionCode, apkUrl, sha256, notes, minSupported}` (not committed; written by `tools/publish_release.py`)
- the APK itself (not committed)

`versionCode` is the Android build number (the number after `+` in `pubspec.yaml`). The app offers an update when it is higher than the installed build, downloads `apkUrl` (HTTPS only), and refuses to install unless the file's SHA-256 equals `sha256`. Builds older than `minSupported` get a required, non-dismissable update.

```bash
python3 server/tools/publish_release.py PATH/TO/Powwot-x.y.z-N-YYYYMMDD.apk \
    --version-name x.y.z --version-code N --notes "What changed" \
    --out /workspace/deploy/powwot-YYYYMMDD
```

Upload `download/<apk>`, then `download/version.json` last so the app and page only see the new version once the APK is in place. Nothing in this folder is deployed automatically.
