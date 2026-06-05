# War Map

Wardriving map that calculates and routes based on distance untraveled previously.

## License

**[Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 (CC BY-NC-ND 4.0)](https://creativecommons.org/licenses/by-nc-nd/4.0/)** — a standard, lawyer-drafted license. Full legal text: [LICENSE](LICENSE).

| Your preference | How CC BY-NC-ND covers it |
| --- | --- |
| Download & personal use | Allowed (noncommercial, with attribution) |
| Fork with **Talaxin** as author | Allowed if attribution is kept ([BY](https://creativecommons.org/licenses/by-nc-nd/4.0/deed.en)) |
| Personal tweaks (e.g. colors) for yourself only | Allowed to *make* adaptations; **not** to *share* them ([ND](https://creativecommons.org/licenses/by-nc-nd/4.0/deed.en)) |
| No rebranding / no shared modified builds | Sharing **Adapted Material** is not permitted ([ND](https://creativecommons.org/licenses/by-nc-nd/4.0/deed.en)) |
| No selling / commercial use | Not allowed ([NC](https://creativecommons.org/licenses/by-nc-nd/4.0/deed.en)) |

> **Note:** Creative Commons [recommends against using CC licenses for software](https://creativecommons.org/faq/#can-i-apply-a-creative-commons-license-to-software). This is still the closest *standard* match to your rules. For a software-specific alternative, see [PolyForm Noncommercial](https://polyformproject.org/licenses/noncommercial/1.0.0/) (allows sharing modified noncommercial builds — looser than ND).

This repository includes a **placeholder iOS app** (v0.0.1) and a [Feather](https://github.com/khcrysalis/Feather) / AltStore-compatible `repo.json` source, modeled after [Noir’s repo layout](https://github.com/Talaxin/Noir/blob/main/repo.json).

## Feather sideload source

Add this URL in Feather (Sources):

```text
https://raw.githubusercontent.com/Talaxin/War-Map/main/repo.json
```

The listing shows **War Map** `0.0.1` with a blank gray icon (`warmap.png`).

## Build the IPA

### Quick placeholder (Linux / CI metadata)

Creates `build/WarMap.ipa` with correct bundle metadata for the source feed. **Not installable** until replaced with a compiled binary.

```bash
python3 scripts/generate_blank_icon.py
python3 scripts/build_placeholder_ipa.py
python3 release_esign.py --description "Initial placeholder release."
```

### Installable build (macOS + Xcode)

1. Open `WarMap.xcodeproj` in Xcode.
2. Set your **Signing & Capabilities** team.
3. Product → Archive, then export a development/ad-hoc IPA, **or** run:

```bash
python3 scripts/generate_blank_icon.py
xcodebuild -project WarMap.xcodeproj -scheme WarMap -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/WarMap.xcarchive archive
# Export with your provisioning profile, then:
python3 release_esign.py --description "Signed War Map build."
```

GitHub Actions (`.github/workflows/build-ipa.yml`) builds an unsigned IPA on `macos-14` when `WarMap/` changes on `main`.

## App metadata

| Field | Value |
| --- | --- |
| Display name | War Map |
| Bundle ID | `com.talaxin.warmap` |
| Version | `0.0.1` |
| Min iOS | 15.0 |

## Release helper

`release_esign.py` syncs `repo.json` version fields and IPA size from `build/WarMap.ipa` (same pattern as [Noir’s release script](https://github.com/Talaxin/Noir/blob/main/release_esign.py)).

```bash
python3 release_esign.py --bump --description "Your release notes."
```
