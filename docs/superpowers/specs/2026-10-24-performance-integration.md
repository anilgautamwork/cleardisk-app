# ClearDisk performance integration

The owner approved adding all WhySlow features to the existing ClearDisk app on October 24. Preserve ClearDisk's name, storage workspace, iCloud Doctor, Mac checks, license and update feed. This implementation uses the existing SwiftUI/macOS 15 stack and the sibling source at `/Users/mac/hdcopy/personal/new-project`.

## Included surfaces

- Performance overview: live CPU, memory pressure, thermal state, uptime, storage pressure and locally explained findings.
- Processes: app/helper grouping, filtering, stable selection and detailed curated explanations. Unknown processes remain unknown; explanations are not malware verdicts.
- Background Items: launch agents, daemons and app login items, observed running state and links to system settings. Coverage remains explicitly partial.
- Internet: connection type, available Wi-Fi evidence, per-app bandwidth and a user-confirmed Apple networkQuality speed test. This test uses the network and may consume substantial data.
- Browser review: Chrome, Brave and Edge tab/window review, duplicate and selected-tab closing, window merging and extension estimates. Browser automation is requested only after the permission primer; private windows remain excluded from cleanup.
- Usage: current CPU/memory charts, local 30-day history and conditional hardware advice with an insufficient-data state.
- Optional menu-bar status, monitoring pause/resume, presentation options, history controls and opt-in login startup.
- Confirmed ordinary app quit, separately confirmed Force Quit, Spotlight reindex and macOS restart. No action runs during QA against real user apps or files.

## Architecture and choices

Keep the sibling engine in a separate PerformanceCore module and adapted views in PerformanceUI. This avoids Core/type collisions and preserves test coverage. A PerformanceCoordinator bridges navigation and the current ClearDisk entitlement. The host owns licensing, activation and Sparkle; WhySlow checkout, receipts, updater and app entry point are not imported. Standalone WhySlow remains untouched. Migrating separately purchased WhySlow licenses would require an explicit backend migration, which this change does not perform.

One Performance item in ClearDisk's sidebar exposes the five feature screens through a segmented control. Storage suggestions navigate inside ClearDisk. Monitoring starts when Performance is visited; optional menu-bar monitoring continues outside that surface. Defaults do not register login startup or request browser permissions. History lives under Application Support/ClearDisk/Performance and does not overwrite either product's license or WhySlow history.

Reusing the entire separate app shell would duplicate navigation, updater and payment flows. Rewriting the engine would risk losing tested behavior. Importing isolated modules with the host bridge preserves the most existing behavior while giving users one app.

## Failure paths and acceptance

Recheck entitlement at confirmation execution. Block self/system-process termination and overlapping actions. Keep ClearDisk's existing file-operation termination guard and include active performance actions. Bound subprocess execution and drain stdout/stderr concurrently. History deletion applies only to regular history files, excluding symlinks and matching directories. Display missing data and catalog failures rather than invented metrics.

Run the complete Swift test suite, universal release build, packaging/resource/entitlement checks and native UI inspection at the minimum supported window and a larger window. Do not claim live release, notarization, paid activation, live browser mutation, administrator reindex or restart validation from a local build. Preserve production artifacts, website and feed until a release is requested.
