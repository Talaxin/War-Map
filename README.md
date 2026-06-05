# War Map

Wardriving navigation for iOS — plan routes, remember roads you've driven, and prefer untraveled distance with the New Roads slider.

## License

**[PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)**

Full legal text: [LICENSE](LICENSE)

**Attribution:** Keep the `Required Notice` in [LICENSE](LICENSE) and credit **Talaxin** / [War-Map](https://github.com/Talaxin/War-Map) as the original source in forks.

## Install (Feather / AltStore)

Add this source URL:

```text
https://raw.githubusercontent.com/Talaxin/War-Map/main/repo.json
```

Then install **War Map** from the source listing.

## Build the IPA (macOS + Xcode)

1. Open `WarMap.xcodeproj` in Xcode.
2. Set **Signing & Capabilities** if installing on a device.
3. Archive and export, **or** from the repo root:

```bash
python3 -m venv .venv && .venv/bin/pip install Pillow
.venv/bin/python3 scripts/sync_app_icon.py
xcodebuild -project WarMap.xcodeproj -scheme WarMap -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/WarMap.xcarchive archive \
  CODE_SIGNING_ALLOWED=NO
mkdir -p build/ipa-export/Payload
cp -R build/WarMap.xcarchive/Products/Applications/WarMap.app build/ipa-export/Payload/
cd build/ipa-export && zip -qr ../WarMap.ipa Payload
cd ../..
.venv/bin/python3 scripts/patch_ipa.py
```

GitHub Actions (`.github/workflows/build-ipa.yml`) builds an unsigned IPA on pushes to `main` that touch app sources.

## Release

Bump the marketing version, rebuild the IPA, then refresh Feather metadata:

```bash
python3 scripts/bump_version.py
# rebuild IPA (see above)
python3 scripts/patch_ipa.py
python3 release_esign.py --description "Your release notes."
```

Commit `build/WarMap.ipa`, `repo.json`, and `WarMap.xcodeproj/project.pbxproj`, then push to `main`.

## App metadata

| Field | Value |
| --- | --- |
| Display name | War Map |
| Bundle ID | `com.talaxin.warmap` |
| Min iOS | 16.0 |
