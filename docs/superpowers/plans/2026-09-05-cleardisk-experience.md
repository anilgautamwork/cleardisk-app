# ClearDisk experience refresh implementation plan

**Goal:** Refresh the native and web experience using the supplied design references, repair treemap loading feedback, improve reading and disk-access onboarding, and defer Talivia until after launch per owner.
**Architecture:** Shared violet identity; native graphite surfaces and Apple-inspired pale website reading surfaces. Native scan and treemap state reflect real work; heavy layout moves off the main actor with stale-result protection. Website keeps SSR SEO content, adds bounded motion and a richer product-led hero. Talivia is paused; no integration is included.
**Tech Stack:** SwiftUI/macOS 15, Swift 6; React/Vinext/Cloudflare.
**Design authority:** User requests autonomous design using supplied repositories. Adopt Raycast spacing, dark surface ladder, thin borders and product-first composition; retain ClearDisk mark and violet CTA. UI UX Pro Max provides loading, keyboard, contrast and reduced-motion rules. Reject generic luxury/fashion palette output for this utility.

## Global constraints
- Keep ClearDisk name and $10 planned license. This remains a preview, not finished 1.0.
- Preserve deletion safeguards and test-only checkout. Do not add live billing.
- Native filesystem scans remain local. Website analytics must not receive local filenames or scan results.
- Do not invent progress percentages; Reduce Motion disables decorative loops and transforms.
- Website stays single page owner; Worker production API ownership unchanged. Private preview stays noindex.
- App preview version 0.1.3 build 4 is set by controller during packaging, not native implementer.

### Task 1: Native interface and treemap responsiveness
**Files:** Sources/ClearDiskApp/{UI,ContentView,WelcomeView,TreemapView,ClearDiskApp}.swift; focused Core helper/tests if needed.
- [x] Trace scan completion and treemap layout; record evidence of synchronous work and missing feedback.
- [x] Implement a premium graphite native shell with crisp typography, compact storage summary, strong navigation, redesigned welcome and scan workspace. Adapt existing views to semantic dark-safe surface/text tokens so readable everywhere. Keep native controls accessible.
- [x] Add honest animated scan feedback with measured files/bytes, stage text and no fake percent. Respect accessibilityReduceMotion.
- [x] Give treemap immediate skeleton/status while actual layout runs off main thread. Cancel/ignore obsolete work after resizing, drill or tree changes; preserve existing drill/selection/deletion safeguards. Add explicit empty state.
- [x] Add meaningful tests for extracted layout or async ordering invariants; run Swift tests and debug build. Do not release/notarize or modify website. Write report with exact test evidence and known limits.

### Task 2: Website art direction and motion
**Files:** website/app/{page.tsx,globals.css}, website/components/product-demo.tsx, new bounded motion/hero component.
- [x] Apply Raycast-inspired graphite tokens and product-led split hero, concise SEO H1, rich illustrated storage map and compact controls.
- [x] Add interactive scan illustration, purposeful entrance/hover/map transitions and Reduce Motion fallback; content remains readable without JS. No looping offscreen WebGL work.
- [x] Preserve all SEO guide routes and structured data. Build/test/typecheck/lint and HTTP regression checks.

### Task 3: Talivia analytics — PAUSED BY OWNER
Owner explicitly paused Talivia on 2026-09-05. No tracker, analytics dependency or service setup will be added. Revisit after launch.

### Task 4: Review and release
- [x] Review native and website diffs; resolve blocking findings.
- [x] Build universal 0.1.3 app/DMG, sign/notarize/staple, verify. Update website binary/version/size.
- [x] Publish private website exact verified source; update handover and deliver new installer and recorded deferred production work.

## Execution record

Native commits 5e4a929 and 7d1b65d: 21 Swift tests pass, debug build succeeds. Review confirmed detached work uses an unpublished tree (scan reports) or immutable geometry snapshots (treemap), with stale-result guards. Fixed contrast and reduced-motion toast findings. Native welcome and active scan visually inspected at 1100px width; live file/byte counts and animation observed. No end-to-end speed benchmark asserted. Post-delete report rebuilding and initial bounded snapshot extraction remain main-isolated.

Website: Raycast reference and UI UX Pro Max used; split hero, labelled scan illustration, content entrance and map interactions, responsive refinements. Existing 12 tests, typecheck, lint and compiled12-route SEO HTTP pass. Review minors (paragraph alignment, map accessible name, privacy wording, narrow map spacing) corrected.

User also requested design-plugin installation: Product Design, Frontend Design Premium and Figma installed and enabled via Codex plugin CLI; UI UX Pro Max and Frontend Design installed as local skills. Frontend Design Premium resolver reports bundled upstream MATCH. Account access for Figma not exercised.

Additional native UI verification: a real home scan completed and System Data rendered; treemap entry, folder drill-down and Back worked. Visual inspection exposed low contrast in the inherited bright treemap tile palette; darkening those category hues before final packaging. No deletion actions were performed.


## Owner steering: Apple-style reading and fewer access interruptions

2026-09-05: new bounded refinement uses plugin87/ux-ui-agent-skills Apple reference. Replace website Geist with native system fonts, pale neutral reading surfaces, centered hero and larger text; keep dark product examples and accessible violet actions. Remove the mounted decorative shader, retain useful scan illustration and reduced-motion support. Main app action becomes Scan my disk, gate root scans centrally, guide access inline before touching the disk. macOS still controls permission approval; avoid misleading guarantees. The previously verified 0.1.2 package is superseded by 0.1.3 after this change.

- [x] Read linked UX/UI repository and Apple reference; use guidance in website implementation.
- [x] Apply typography and light editorial reading theme, preserve SEO and functionality.
- [x] Finish native permission-first flow, tests and review.
- [x] Package/sign/notarize latest 0.1.3 and publish exact website source.


Native access refinement: bbb702e + edf4f0a. 25 tests pass; debug build passes. Isolated app UI QA confirmed Scan my disk routes to inline disk access before scanning, Check access remains inline without granting anything, and Back returns to welcome. Layout inspected at 1100×752. No OS permissions were changed and no full-disk scan was started in this follow-up. Code review found no blocker; fixed repeated-relaunch race and clarified instruction wording. FDA detection is a conservative heuristic because Apple provides no public status API; additional OS restrictions/prompts remain possible.

Website static review confirmed light root/dark demonstration token scoping, light portal dialog, retained SSR/SEO and interactions. Fixed mobile guide CTA/header button specificity. Tested key new contrast pairs: body7.52:1, muted5.79:1, white on action6.61:1, guide body10.01:1. No browser UI QA was requested; native UI was visually checked.


Final0.1.3build4 release through edf4f0a: universal x86_64/arm64, app and DMG notarized/stapled, Gatekeeper accepted. DMG2,999,122 bytes, SHA-256 bf00af0bb97d883be8f4cd9968e5c0634ac2b91176384734853fb866afc4b875. Copied exact verified binary to website/public/ClearDisk.dmg; download instructions/version/size updated.


Final web build/typecheck/lint successful;12 unit tests and12-route compiled HTTP checks pass. Served DMG hash matches native release. Website commit98ac3329564acd7d27d5cdfcc62fd94d59b5e6eb saved as Sites version5, deployment appgdep_6a9b416c52288191b3f01a4f56e88cea succeeded privately. Owner-only audience preserved. Root handover has exact release/source/deployment details.
