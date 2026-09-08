# iCloud Doctor inside ClearDisk — audit and proposed integration

Date: 2026-09-09. Status: proposed design, not implemented or released.

## Recommendation

Add iCloud Doctor as a section of ClearDisk, sharing its existing license and brand. Keep the homepage focused on System Data; use a dedicated iCloud landing page for iCloud search intent. The user now wants a combined product, superseding the older separate-SyncDoctor positioning. Do not revive the old separate $9.99 price or development entitlement bypass.

The useful promise is: **Understand iCloud Drive sync problems and the space its local copies use.** It is not an automatic repair of all iCloud services. Removing a downloaded copy frees Mac storage, not iCloud account storage. Removing an original from iCloud affects other synced devices.

Alternatives considered: a separate SyncDoctor product duplicates distribution, payments and marketing; articles alone can help acquisition but do not implement the requested diagnostic. Integrating the diagnostic is recommended, with explicit limits and a tested release.

## Audit: what exists today

### ClearDisk

Current source is ahead of the top of docs/HANDOVER.md. Git HEAD at audit: 460e1c5. Scripts/Info.plist declares 1.0.0, build 6. Sources/Core/License.swift, Sources/ClearDiskApp/License.swift and UnlockSheet.swift implement signed receipts, activation, license persistence and the cleanup gate. Website app/api includes checkout, key, activate, recover and Stripe webhook routes. These are implemented code, not proof of an end-to-end real purchase/refund test during this audit.

Native features include disk scanning, System Data, developer junk, categories, browse, treemap, large files, search, shared removal confirmations and Undo. Cloud folders are classified and protected; there is no iCloud Doctor navigation or metadata scanner in ClearDisk yet. Existing cloud protections must remain intact.

releases/v1.0.0.json records the released DMG as 3,062,248 bytes, SHA-256 39932616d95db1621c7b5911b748daf7a9c91a4c881dcf72ed88e20f2a90220b. This audit did not re-notarize or replace that artifact. The website has expanded beyond the older 17-guide handover and already discusses iCloud local storage. Reconcile the current guide registry before adding pages.

### SyncDoctor

Located at /Users/mac/hdcopy/personal/iclouddoctor. Read its AGENTS.md, README.md, Foundation core, SwiftUI state/views and history implementation. Read the ChatGPT task **iCloud Keyword Watch**, including its prototype specification and subsequent search recommendations.

Implemented: public Foundation metadata reader, scanner, locator, cloud-only and waiting tables, problem classifier, raw inspector, download request, uploaded-state-gated local-copy eviction, and a SwiftData history prototype. The prior project's AGENTS.md records real metadata observations from milestone 1; this audit independently ran its unit tests but did not reproduce those real-file observations.

Missing: the Storage screen is literally StoragePlaceholderView; no Move to Mac Only transaction exists; no complete health-check service; no integrated ClearDisk navigation/license/release. Entitlements remain a development abstraction in SyncDoctor.

Issues requiring correction before reuse:

- ScanHistoryStore records only nonhealthy items. A healthy intervening scan cannot clear the old pending chain reliably; stuckUploadPaths compares the first/last historical snapshots rather than a current uninterrupted sequence.
- The suggested Documents/SyncDoctor Local destination may itself be in iCloud. An archive must resolve outside all known synced locations, or be refused.
- ProblemClassifier treats metadata noise such as .DS_Store upload errors as useful problems and can suggest overly broad actions. Cloud-only is a normal storage state, not a fault.
- Eviction currently checks only isUbiquitous and isUploaded. Add fresh metadata checks for file kind, conflicts, errors, transfers, scope and missing values; never apply a blanket folder eviction from a summary row.
- DatalessMaterializationPolicy return values are ignored by the scanner. Fail closed if the no-materialization policy cannot be installed; restore thread policy after the synchronous walk. Do not alter unrelated ClearDisk filesystem operations process-wide.
- Unbounded scan events and complete per-item collections need a bounded product policy, responsive cancellation and explicit partial results. Incomplete scans cannot report overall health or extend pending history.

### Verification completed in this audit

- ClearDisk: swift test — 47 tests pass.
- SyncDoctorCore: swift test — 6 tests pass.
- These baseline tests do not validate the missing archive workflow or prove iCloud synchronization behavior on a real problematic account.
- No app source, live website, cloud settings or user documents changed during the audit.

## Proposed product scope

### Entry and overview

An iCloud Doctor sidebar destination is available without a full-disk scan. It starts with **Scan iCloud Drive**, a concise explanation of access and an explicit user click. It does not automatically open iCloud on launch or bypass macOS permission prompts. Disk scanning and iCloud scanning retain independent state and cancellation.

Display observed upload/download errors, conflicts, pending transfers, cloud-only files and measured allocated local bytes. Unknown metadata stays Unknown. Access-denied, unavailable, cancelled, truncated and empty states are distinct. A progress indicator describes scanning items; it must not invent transfer percentages.

Use ClearDisk's existing UI palette and system typography. Reuse the globally installed Impeccable and Emil design guidance for hierarchy, keyboard access, visible feedback and reduced motion. The section must remain usable at the app's minimum supported size.

### Problems and storage

Searchable, sortable file results with path, logical bytes, allocated bytes, state and actionable explanations. Filters: errors/conflicts, waiting/uploading, cloud-only, local copies, large files and modification age. Modification age is not evidence that a file is unused. Folder totals aggregate inspected descendants and clearly label incomplete coverage.

Pending history stores consecutive comparable observations locally, with bounded retention and a Clear History control. Healthy, missing, changed, unknown or incomplete observations reset the evidence. Only two or more matching observations separated by the configured interval can produce **potentially stuck**; this is not proof of uninterrupted failure between observations.

### Actions

1. Reveal in Finder and open iCloud settings/support are always available when applicable.
2. Download Now explicitly requests a download and shows subsequent observed state; request accepted is not download completed. Explain disk-space and network implications.
3. Remove Local Download is an individually confirmed licensed action. Re-read metadata immediately before requesting eviction. Refuse unsupported types, changed scope, unknown upload state, unsynced data, ongoing transfers, conflicts and errors. Show that it frees Mac storage only and requires downloading again for offline use. Report observed outcome rather than claiming savings from logical size.
4. Archive to Mac is a separate, reviewable operation: choose a verified nonsynced destination; materialize only through explicit download requests; copy without overwrite; coordinate access; verify contents and source stability; retain the original on any failure. A verified copy is a backup, not iCloud space recovered. Explicitly offer a second review of the cloud original in Finder. Automatic cloud deletion is excluded from the first integrated release; ClearDisk's protected-cloud deletion policy stays intact. This scope trades one final Finder step for preserving the existing audited deletion boundary.
5. Keep Downloaded uses Finder guidance unless a supported public third-party API is verified. Do not label Download Now as persistent pinning. Conflict resolution remains in the owning app/Finder.

Archive verification needs byte integrity, not size alone. Use a unique staging destination, no silent overwrite, mutation checks and cancellation. Do not silently delete the user's only verified copy as a rollback. Support regular files first; packages/folders require a manifest of every member, no symlink traversal, per-member verification and a clean completion state before presenting the folder as verified. Unknown providers or destinations are refused with an explanation.

### Health checks and limitations

Check accessible Drive state and available local capacity. Network reachability is a separate observation, not an Apple service-health verdict. Link to Apple's official status page. The app cannot claim a complete account quota, inspect arbitrary Photos/Notes/Messages/private containers, force Apple's server state to refresh, or guarantee synchronization repair.

No Apple-account credentials, private APIs, brctl reset recipes or scraping of System Settings. No file names, contents or scan reports sent to website analytics. Existing license network behavior remains separate.

### Website and search

Keep one ClearDisk domain and the System Data homepage. Add /icloud-doctor only when the downloadable app actually includes the verified feature. Prefer a single strong page per intent, with links to existing iCloud storage content:

- iCloud Drive stuck uploading / waiting to upload / not syncing on Mac: diagnostic and pending-transfer intent, grouped to avoid duplicate articles.
- iCloud storage full but it isn't / still full after deleting: account-versus-device explanation with native Apple steps, no claim the Mac scanner repairs account quota.
- Existing iCloud Drive taking up space on Mac page: local-copy storage intent; update it with the shipped feature's real capabilities.

The prior chat's popularity estimates and weak-competition statements are hypotheses, not current measured keyword data. No current monthly volume was authenticated in this audit. Broad iCloud queries often concern iPhone Photos/backups and may convert poorly for a Mac Drive utility. Measure relevant query impressions and downloads separately; do not forecast revenue from keyword volume alone.

Primary references rechecked during audit:

- https://support.apple.com/en-ae/guide/mac-help/mchlc994344b/mac — Finder iCloud status.
- https://support.apple.com/en-gb/guide/mac-help/mchl1a02d711/mac — file/folder controls.
- https://support.apple.com/en-us/102670 — device versus iCloud storage.
- https://developer.apple.com/documentation/foundation/filemanager/evictubiquitousitem(at:) — public local eviction API.
- https://developer.apple.com/documentation/foundation/filemanager/isubiquitousitem(at:) — public ubiquity check and upload-state guidance.

## Implementation sequence and release criteria

1. Vendor the relevant SyncDoctor core into this repository, recording its origin, so ClearDisk builds independently of a sibling checkout. Keep it a separate Foundation module; use the current ClearDisk license, not DevelopmentEntitlementService.
2. Correct metadata classification, no-materialization handling, history and cancellation with regression tests. Preserve all existing ClearDisk tests and cloud-removal refusals.
3. Add the native section, storage filters, explanations and safe confirmed actions. Use fixture-only tests for destructive paths; live QA is read-only unless the owner supplies dedicated disposable test data.
4. Implement and test the verified archive operation, including insufficient space, collisions, cancellation, partial copies, source changes, symlinks, dataless items and synced destinations. Do not claim this is complete based on a successful ordinary copy.
5. Verify native UI, accessibility, empty/error states and large-result responsiveness. Test explicit download/eviction on dedicated disposable iCloud fixtures before release; report any metadata unavailable on the test environment.
6. Produce a new signed/notarized universal app and DMG, verify release hashes, then update product pages/download version, metadata, internal links and sitemap. Check the website at desktop and narrow widths and run its current checks before deployment. Preserve live payment configuration and owner data.

This document is the reviewable scope. Implemented and proposed features must remain clearly distinguished until the release criteria pass.
