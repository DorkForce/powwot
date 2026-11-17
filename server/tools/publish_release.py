#!/usr/bin/env python3
"""Stage a Powwot release for upload to the download page.

Usage:
  python3 server/tools/publish_release.py APK --version-name 0.1.2 --version-code 3 \
      --notes "What changed" --out /workspace/deploy/powwot-YYYYMMDD [--min-supported 1]

Writes under OUT (mirroring the powwot.dorkforce.com doc root):
  download/<apk file name>      the APK
  download/version.json         {versionName, versionCode, apkUrl, sha256, notes, minSupported}
  download/index.html           server/public/download/index.html with the fallback version, link and checksum filled in
  download/qr.svg               copied unchanged
Nothing is uploaded; upload the files with cPanel File Manager after approval.
"""
import argparse
import hashlib
import json
import pathlib
import re
import shutil

BASE = 'https://powwot.dorkforce.com/download/'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('apk')
    ap.add_argument('--version-name', required=True)
    ap.add_argument('--version-code', type=int, required=True)
    ap.add_argument('--notes', default='')
    ap.add_argument('--min-supported', type=int, default=0)
    ap.add_argument('--out', required=True)
    a = ap.parse_args()

    apk = pathlib.Path(a.apk)
    out = pathlib.Path(a.out) / 'download'
    out.mkdir(parents=True, exist_ok=True)
    sha = hashlib.sha256(apk.read_bytes()).hexdigest()
    shutil.copy2(apk, out / apk.name)

    version = {
        'versionName': a.version_name,
        'versionCode': a.version_code,
        'apkUrl': BASE + apk.name,
        'sha256': sha,
        'notes': a.notes,
        'minSupported': a.min_supported,
    }
    (out / 'version.json').write_text(json.dumps(version, indent=2) + '\n')

    src = pathlib.Path(__file__).resolve().parents[1] / 'public' / 'download'
    html = (src / 'index.html').read_text()
    html = re.sub(r'(<strong id="version-name">)[^<]*', r'\g<1>' + a.version_name, html)
    html = re.sub(r'(<span id="version-code">)[^<]*', r'\g<1>' + str(a.version_code), html)
    html = re.sub(r'(<a class="btn" id="download" href=")[^"]*', r'\g<1>' + apk.name, html)
    html = re.sub(r'(<code id="sha">)[^<]*', r'\g<1>' + sha, html)
    (out / 'index.html').write_text(html)
    shutil.copy2(src / 'qr.svg', out / 'qr.svg')
    print(json.dumps(version, indent=2))


if __name__ == '__main__':
    main()
