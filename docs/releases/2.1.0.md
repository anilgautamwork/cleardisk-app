# ClearDisk 2.1.0 — Mac checks

Status: released on 4 October 2026 (local date). ClearDisk 2.1.0, build 12 is live on cleardisk.app, the signed Sparkle feed and GitHub Releases. App source: 17bcf1dcadc178c86095e98400366241d9a211d5.

## Included in ClearDisk

Mac checks is available in the existing sidebar before or after a disk scan. Its two checks run off the main thread, can be cancelled, retain results while navigating, and never launch inspected apps or remove files. Existing licensing, cleanup and iCloud behavior are unchanged.

Apple Intelligence measures allocated regular-file bytes in three recognized MobileAsset families: UAF_FM_GenerativeModels, UAF_FM_Visual and UAF_FM_Overrides. It checks AssetsV2 plus the InstallWithOs and RequiredByOs preinstalled roots. Missing, inaccessible and partial locations are distinct. Hard links are counted once, symbolic links are not followed, and unrelated assets are excluded. These names were observed on the development Mac; they are an implementation heuristic, not an Apple-supported inventory API. No blanket 30 GB requirement, complete system total or reclaimable-space promise is made. APFS shared extents and snapshots can produce a different physical usage figure. Use System Settings to manage features; no model deletion or security bypass is offered.

Intel apps inventories /Applications and ~/Applications, including subfolders. Bounded Mach-O header reads classify the main executable as Intel-only, Universal, Apple silicon, legacy 32-bit Intel or undetermined. Universal slices are validated, malformed headers stay undetermined, and executable paths may not escape their bundle. Intel-only results appear first. Embedded helpers, plug-ins, extensions and other install locations are explicitly outside this check. Finder shortcuts help users find an app and obtain its developer's update; nothing is uninstalled.

## Sources checked 3 October 2026

- https://support.apple.com/en-gb/102527 — Rosetta is generally available through macOS 27 on Apple silicon; macOS 28 retains a limited older-game exception. Users should update apps and separately installed components. The scanner does not determine game exceptions.
- https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment — confirms the general-purpose transition timeline.
- https://support.apple.com/en-gb/121115 — current storage requirements vary by supported hardware. Does not support treating 30 GB as a universal footprint. The app links this guidance but reports measured assets rather than a fixed estimate.
- Local directory names under /System/Library/AssetsV2 and its two preinstalled subdirectories were inspected without changing permissions or assets.

## Validation

- 76 Swift tests pass: 60 Core and 16 SyncDoctorCore, including 13 new Mac checks tests.
- Tests cover thin/fat Mach-O, both byte orders, 32/64-bit universal tables, malformed/truncated/overlapping slices, scripts, bundle path escapes, aliases, nested helpers, duplicate roots, missing roots, hard links, unrelated assets, unreadable folders and cancellation.
- Universal release build (arm64 and x86_64) passes; both executable slices retain macOS 15.0 minimum deployment metadata.
- Native preview checked at the app's normal minimum-width window: pre-scan access, both report tabs, readable layout, actual scans and permission feedback. The real inventory found one Intel-only main executable among 67 apps; file/lipo independently confirmed x86_64. Four apps remained undetermined. This is one local observation, not a typical-user statistic.
- The preview could not read protected model contents. Verified “No readable model files”, “Not measured”, partial-result explanation and Full Disk Access shortcut; no zero-footprint claim. Actual model-byte totals on this machine remain unverified. Measurement correctness was exercised with generated files, including permission failures; no personal file was removed or permission changed.
- Local ad-hoc preview: .build/MacChecksPreview/ClearDisk.app (separate preview identifier; production app preserved). It uses the universal release executable. It is not a notarized public installer.

## Published release — 4 October 2026

The earlier missing csvcompare notarization-profile blocker was resolved after the owner unlocked the Mac and restored the existing credentials. No signing or update key was replaced. Scripts/release-direct.sh completed for the normal production app identifier.

- App and DMG notarizations accepted; both staples validated. Strict code signature verification and Gatekeeper assessment passed. Developer ID: TECHMARBLES WEB SOLUTIONS PRIVATE LIMITED (CH96562777).
- App notarization: 7cf3b942-2840-456a-bae3-e6cf387df8d7; DMG: 9ce6befb-de0b-42a2-83ef-18781e678971.
- Universal package UUIDs match the built executable. Sparkle archive and feed signatures verified using the existing pinned key. Previously published update archives retained.
- DMG: 6,287,199 bytes; SHA256 b4ba1ad14058d3be8e221d35566af8d6fad3926fc92c67a33869384d4b2abd99.
- Website source: 36a1ea1; Cloudflare Worker: 1d5e854b-ca59-4a38-97fd-80cef4d2146b.
- Website download: https://cleardisk.app/download ; direct DMG: https://cleardisk.app/ClearDisk.dmg .
- Immutable update: https://cleardisk.app/updates/ClearDisk-2.1.0-12.dmg ; feed: https://cleardisk.app/updates/appcast.xml .
- Published GitHub release: https://github.com/anilgautamwork/cleardisk-app/releases/tag/v2.1.0 . Uploaded DMG digest matches the website DMG.

### Final verification

All 76 Swift tests and 55 website tests passed, along with website typecheck, lint, production build and all 176 local/live HTTP SEO checks. Desktop download and 390px features layouts were inspected; no horizontal overflow. Live DMGs and feed match local verified artifacts. Anonymous /analytics and /api/analytics return 401. QA HTTP requests used ClearDisk-QA; updater archive requests are excluded from primary download counts.

The signed production app ran both checks. Intel inventory found 67 apps, one Intel-only main executable and four undetermined apps on this Mac. Protected Apple Intelligence contents remained unreadable; the UI correctly reported partial results, “No readable model files” and “Not measured”. No new disk permissions were granted, no files removed, and no real model-byte total is claimed.

End-to-end Sparkle upgrade was tested from the installed 2.0.0 build 11: Check for Updates found 2.1.0, downloaded it, installed and relaunched successfully. About shows 2.1.0 (12); Mac checks appears in the sidebar and the existing developer-testing license remains activated. The transient process-not-found response during relaunch was resolved by reacquiring the relaunched app. This verifies the existing developer license path; no new paid-license activation was exercised during release QA.

Existing $10 license, payment mode, cleanup behavior and iCloud behavior are unchanged. 2.0 users can update from ClearDisk → Check for Updates. 1.1.1 and earlier need a manual download. Apple Rosetta support page https://support.apple.com/102527 was rechecked during release; Intel-only findings do not establish compatibility of plug-ins or older-game exceptions. No search indexing or ranking claim is made.

## GitHub workflow recovery

Publishing v2.1.0 triggered the existing tag workflow, which failed because the tagged source lacked releases/v2.1.0.json. The already published, notarized website and GitHub assets were unaffected. Added the manifest pinned to website commit 36a1ea10983eebb54f61834ab7a5ee0c70f9d324, release notes and a manual recovery input. Existing releases are now verified by size/digest instead of overwritten. The original app tag was preserved.

Recovery commit bb167ae is on main. The exact workflow scripts passed locally; GitHub recovery run https://github.com/anilgautamwork/cleardisk-app/actions/runs/37157573051 completed successfully, including download verification and existing-release verification. Original failed run 37157309384 remains historical; rerunning its unchanged tagged workflow would still lack the manifest. Future releases must commit their manifest and notes before creating the tag.
