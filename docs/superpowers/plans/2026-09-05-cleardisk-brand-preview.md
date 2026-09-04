# ClearDisk brand consistency and preview build plan

**Goal:** Match website download controls and native app identity, then deliver a fresh signed/notarized preview without presenting unfinished 1.0 features as shipped.

**Architecture:** Reuse one DownloadButton on the website. Native AppIcon supplies the same C/sparkle design to the running app and packaged icon renderer. Keep semantic file-type and safety colors; use violet for brand actions and selected states.

**Scope:** Branding correction and installable 0.1.1 preview. Does not mark licensing, unified removal, dark mode, two-pass scan or production checkout complete.

- [x] Reuse the primary lavender DownloadButton in the header, with consistent label/icon and compact sizing. Remove the mismatched light variant and unnecessary badge.
- [x] Match favicon to the shared website mark and record exact palette/usage.
- [x] Replace native blue cylinder with violet C/sparkle. Use AppIcon as the single renderer for Dock/welcome and packaged icns; regenerate during packaging.
- [x] Apply native light-background violet accent and selection colors. Preserve red destructive and safety/category colors.
- [x] Bump preview to 0.1.1 build 2, add a visible preview note, run Swift tests and universal release build.
- [x] Preserve the prior generated distribution before release script replaces dist; sign/notarize app and DMG using existing credentials; verify both architectures and Gatekeeper.
- [x] Replace website preview download with verified new DMG and update version/size/copy. Run website tests/build/HTTP checks, review and publish private preview.
- [x] Record exact artifacts and remaining production milestones in handover. Deliver download link; no live billing or public indexing.

Completed: 17 Swift tests; 12 website tests; typecheck/lint/build and SEO HTTP checks pass. Native and website header/hero visually inspected. Apple notarization/stapling and Gatekeeper accepted app/DMG; website serves the identical hash. Website source db2c620413185dd49518bb504d1b23edd538bbfd published privately as Sites version 4. Full 1.0 milestones remain open.
