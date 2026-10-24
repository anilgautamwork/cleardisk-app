# ClearDisk 2.2.0 performance integration

## Source and scope

Imported the existing WhySlow engine, process catalog, fixtures and feature views from `/Users/mac/hdcopy/personal/new-project` at `85e85d4bd15bc5c3e09919e7fe317576d8f9065a`. The sibling repository is unchanged. PerformanceCore and PerformanceUI are separate Swift package targets inside ClearDisk.

The Performance sidebar section contains Overview, Processes, Background Items, Internet and Usage. It includes process explanations, grouped CPU/memory readings, thermal and storage findings, browser review for supported Chromium browsers, per-app bandwidth, an explicit Apple speed test, local history, hardware advice, optional menu-bar monitoring and login startup. Confirmed quit/force quit, Spotlight reindex and restart actions are retained. Storage suggestions navigate to ClearDisk's existing workspace.

ClearDisk owns activation and Sparkle. WhySlow's checkout, license records, updater and standalone CLI executable were not imported. Existing WhySlow licenses are not automatically migrated. Performance diagnostics are free; paid actions consult the existing ClearDisk entitlement at execution time.

## Integration review

- Monitoring defaults off outside Performance; the optional menu bar keeps it running. Login startup remains opt-in.
- Usage history is isolated under `Application Support/ClearDisk/Performance`; cleanup only matches regular generated history files and rejects symlinks/directories.
- System/self process protection, active-operation exclusion, entitlement revocation, deferred license-sheet presentation and no automatic replay after activation were reviewed.
- Subprocess stdout/stderr are drained concurrently and execution has a deadline. Cancellation prevents stale monitor results from being applied. Already-started detached system commands can finish up to their timeout; cancellation does not claim to undo them.
- A native NSStatusItem/NSPopover hosts the optional menu. SwiftUI MenuBarExtra caused a reproducible startup update loop in the combined app on this Mac; removing that scene resolved it. The host uses one main window, matching its shared scan and operation state.
- The sidebar now scrolls at small heights so licensing and navigation remain reachable. Network wording distinguishes a lack of detected issues from verified internet reachability.
- Browser Automation permission is only requested after its primer. The optional speed test explicitly explains Apple's servers and potential data usage.

## Validation on October 24, 2026

- Full `swift test`: **200 passed, 0 failed, 0 skipped** — Core 60, SyncDoctorCore 16, PerformanceCore 119, PerformanceUI 5.
- Universal release build passed for arm64 and x86_64. Mach-O load commands report minimum macOS 15.0 for both slices. The toolchain emitted an x86_64 deprecation warning; this did not fail the build. Existing iCloud compiler warnings remain.
- `git diff --check`, shell syntax checks for both packaging scripts, and plist/entitlement lint passed. No separate Swift lint command is configured. The Impeccable detector returned successfully with no findings for PerformanceUI.
- Preview executable UUIDs match the universal build. Catalog, embedded Sparkle, version/build, Apple Events description and signed-update requirements passed the package checks. Ad-hoc deep/strict signature verification passed.
- Native UI verified: startup, live overview, process filtering and kernel_task protection, background items, network readings, usage charts, settings, browser permission primer/cancel, and settings-to-existing-license-sheet handoff/cancel. Inspected the minimum-size and zoomed desktop layouts.
- Menu-enabled startup passed using a temporary process argument. **The system menu-bar popover's visual/interaction check remains incomplete:** computer-use automation timed out selecting SystemUIServer. No assertion is made that the popover was manually tested.
- Did not grant browser permissions, close user tabs/apps, clear user history, reindex Spotlight, restart macOS, register login startup or run a bandwidth-consuming speed test. Browser parsers/action planning and other engine paths have fixture coverage; live privileged/destructive paths still need a release smoke test on disposable data.

## Artifact and release status

Local preview: `.build/performance-preview/ClearDisk.app`, **2.2.0 (13)**. This preview is ad-hoc signed and has automatic update checks disabled in its preview-only plist. The source release plist retains the existing update policy and feed.

The preview was closed after testing. Production `dist`, the installed app, website, download and appcast were preserved. No commit, push, notarization or publication was performed. Before publishing, finish the menu-bar smoke test, validate permission-dependent actions with disposable fixtures, then use the existing Developer ID/notarization/release process.


## Release preparation — October 24

Owner requested publication after the local preview. Updated the activation-sheet privacy bullet to describe local file scans, rather than claiming the entire app is offline. Full Swift suite repeated: 200 passed, zero failed/skipped. Universal build, strict deep signatures, plist/shell checks and packaged executable UUID checks passed. No separate Swift lint command is configured.

Developer ID signed app notarization accepted: df204305-4da8-4fe1-91c5-b9bb1e0fad78. DMG notarization accepted: 170d0c48-6951-423a-a7c8-f34e8a7833a9. Both stapled tickets validate. Gatekeeper accepted the DMG. The Sparkle feed signature verifies with the existing update key. Archive: 8,343,384 bytes, SHA256 c4eef9f0fb016a4d1598ac2027779b209be187722edecfb08c0954863abde746.

The final signed app launched and displayed live performance data using the existing license. It was closed after inspection. Temporary launch arguments enabled menu-bar startup without changing the saved setting. The menu-bar popover interaction and live permission-dependent/administrative actions remain unverified; no private browsing access was granted and no user apps/files were altered for a demonstration. These limits are retained rather than presented as successful tests. Final publication evidence will be appended after live verification.


## Publication verified

October 24: website source 028ea9a published with Cloudflare version c8e02a7e-4007-4cde-ac8f-cedff1fbf2d3. App source 21ac575 and manifest commit b95cdf2 are on main, tagged v2.2.0. GitHub Actions 40060105899 succeeded; release asset bytes/hash match the manifest. Live signed feed and both DMG routes match staged artifacts. The installed 2.1.0 app completed the production Sparkle download/install/relaunch to 2.2.0 (13), with the existing license preserved.

200 Swift tests and 58 web tests passed with zero failures/skips. All 179 live HTTP SEO checks passed. Menu-bar popover and live privileged/browser actions retain the limitations above. Staged whitespace review found only one extra final blank line in PerformanceCoordinator.swift; check excluding blank-at-EOF passed, with no behavioral edit or post-sign build change. No separate Swift lint command exists.
