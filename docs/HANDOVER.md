# ClearDisk — Developer Handover

## iCloud Doctor 1.1.0 — 9 September 2026 (current status)

ClearDisk 1.1.0 build 7 integrates the repository-local SyncDoctorCore and an independent iCloud Doctor section. Metadata scans, history, search/filter/folder totals, raw inspection, explicit downloads, licensed local-copy removal and verified document archives are implemented. Sources and partial archives are retained; executable/semantic-metadata files are refused. Cloud originals are never deleted by this section. See Sources/SyncDoctorCore/ORIGIN.md and docs/superpowers/specs/2026-09-09-icloud-doctor-integration.md for limits.

The universal arm64/x86_64 app and DMG are Developer ID signed, Apple-notarized and stapled. Release: https://github.com/anilgautamwork/cleardisk-app/releases/tag/v1.1.0 . Public download: https://cleardisk.app/download . DMG bytes 4080467; SHA256 46d891de92a2790cef567d223916c65b2ab8c0ccb73b572f56994344aa55a233. Exact source/artifact binding is releases/v1.1.0.json. Original dist backup is /tmp/cleardisk-before-icloud-release/dist.

Validation: 63 Swift tests pass; independent review corrected unknown-locality and history labels; native pre-scan entry and a read-only metadata scan passed. No live cloud mutations were exercised. Website: 42 tests, typecheck/lint/build, desktop/390px checks, 69 live HTML SEO checks, public DMG hash and private analytics 401 checks passed.

Website now has 52 guides, eight new iCloud articles and /icloud-doctor; sitemap has 64 URLs. Google Search Console HTTPS URL-prefix property is verified under anilgautamwork@gmail.com using the homepage HTML tag; sitemap processed successfully with 64 discovered pages on 9 September. Discovery is not indexing. Domain-wide DNS property remains unverified; it is not required for the canonical HTTPS property. Preserve the public Google verification tag. No Cloudflare DNS records were changed.

Current checkout/license configuration is preserved. Older test-only/preview statements below are historical, not instructions to revert payment settings. Talivia remains paused. The September 13 10:00 IST 30-day marketing schedule is unchanged; its prompt now uses current release/payment state and the current guide registry. Separate website research: docs/research/2026-09-09-icloud-content.md. No keyword volumes were invented, and no external social messages or paid ads were sent.

## Download dashboard and SEO expansion — latest continuation

The website now includes 17 guides (12 newly researched articles), a grouped storage hub and a 20-URL sitemap at https://cleardisk.app/sitemap.xml. All 24 public HTML routes passed rendered SEO checks. New source research, 45-keyword mapping and a 30-day marketing plan are in the separate website repository under `docs/seo/2026-09-05-growth-research.md` and `docs/seo/growth-keywords.csv`. Monthly search volumes are unverified; Search Console access was not available. No social posts, emails or paid ads were launched.

The private download graph is https://cleardisk.app/analytics. Username is `owner`; password is generated locally in ignored `website/.env.analytics-owner` and stored in Cloudflare encrypted secrets. See website `docs/ANALYTICS.md`. It counts successful full DMG requests per UTC day with source labels; it does not measure installs, unique people or completed transfers. GitHub downloads are reported separately. No tracking cookies, IPs, raw referrers or individual visitor records are persisted by the counter. Website counting starts with this deployment. First read: 0 website requests, 1 GitHub download. Testing was excluded from production counts.

Worker deployment: `2d83a170-2791-4a82-89c9-242ae0c3650d`, same personal account and cleardisk.app domain. SQLite daily counters expire after 366 days. Sixteen website unit tests, typecheck/lint, runtime auth/concurrent-count checks and live deployment verification passed. Native app/DMG0.1.4 unchanged. Stripe remains test-only; Talivia remains paused.

## Public Worker deployment and 0.1.4 preview — 5 September 2026 (latest status)

The owner confirmed **cleardisk.app** (not diskclear.app), personal Cloudflare account `anil personal` (`449c51af2c638c0c3c88493d6175228b`). The site is deployed as Worker `cleardisk-website` on its custom domain. Initial deployment version: `4e26c98a-ed7b-4f0b-89ba-cab7a8dfd0ca`; the Stripe test secret was subsequently added through Wrangler encrypted secrets. Never commit `.dev.vars` or credentials.

Repositories supplied by the owner and pushed to `main` using the configured `github-agw` SSH identity:
- App: https://github.com/anilgautamwork/cleardisk-app
- Website (separate repository): https://github.com/anilgautamwork/cleardisk-website
- Signed/notarized preview release: https://github.com/anilgautamwork/cleardisk-app/releases/tag/v0.1.4
- Direct download: https://cleardisk.app/ClearDisk.dmg

ClearDisk **0.1.4, build 5**, macOS 15+, universal arm64/x86_64. DMG: **3,010,640 bytes**; SHA-256 `019b5f104a4ccb3c33c1840033299b90fea7338dcd5bdbc60b3655654cef9ac6`. Both app and DMG are Developer ID signed, Apple-notarized and stapled; Gatekeeper accepts the DMG. Downloaded GitHub and Cloudflare assets match this exact hash.

Every removal entry point now uses a shared choice sheet: Cancel, Move to Trash, red Remove Permanently. Permanent deletion requires exact typed confirmation; Trash remains available in that stage. Batch work runs off the main thread, applies only successful removals, preserves container roots, deduplicates paths and checks protections. App-cache selection excludes unchecked browser caches. Undo only restores successful paths and retains retryable failures. Core coverage: 42 tests pass; debug and universal release builds pass; final independent source review found no blocker. Sidebar Buy for $10 link and test-mode disclosure verified in native accessibility state. No user files were removed during UI verification.

**TEST checkout is explicitly authorized for this launch.** https://cleardisk.app/buy-now is linked in the website header/hero and native sidebar. The deployed API returned HTTP 200 and a verified Stripe `cs_test_` checkout URL. No real charge or license is issued. Native activation and production license fulfillment remain unfinished; do not replace the test secret with a live key to bypass this. Existing checkout deliberately rejects live keys. Talivia remains paused.

Production build uses `npm run build:cloudflare` (`DEPLOY_TARGET=cloudflare SITE_INDEXABLE=true`) then `npx wrangler deploy --config dist/server/wrangler.json`. `npm run deploy:cloudflare` combines these. The default Sites build retains its separate plugin and noindex behavior. Cloudflare compatibility date is `2026-05-22`, the newest accepted by this website's installed workerd binary (the Claude Worker scaffold uses a separate toolchain). Production origin, canonicals and sitemap use cleardisk.app. Worker preview URLs and workers.dev are disabled.

Validation: website typecheck, lint, 12 unit tests; compiled and public HTTPS checks for 12 HTML routes, five complete guide pages, unique metadata/H1s, Article/Breadcrumb schema, internal links, real 404, robots, sitemap and DMG. Public DNS resolvers resolve the new domain; this Mac initially cached NXDOMAIN, so public HTTP verification used the DNS-returned Cloudflare IP with normal HTTPS hostname/certificate validation. No TLS verification was disabled. Search Console verification/submission and ranking performance remain unverified.

GitHub tag workflow `.github/workflows/publish-dmg.yml` downloads the exact website commit's binary, verifies recorded size/SHA-256, and publishes the preview release with checksum using the repository-scoped Actions token. Run `33925460240` succeeded. Release manifest and notes are in `releases/`. Build/sign/notarize locally with `./Scripts/release-direct.sh`; the workflow never receives Apple signing credentials.

Future full licensing work must address issues found in the original plans: strip the CLDK prefix before character normalization; validate the paid ClearDisk product/price before fulfillment; use atomic activation/revocation storage; retry failed license-email delivery; recheck licensing when resuming a pending removal. Claude's isolated `web/` scaffold remains separate and unmodified by this release.

Written 2026-09-05 when work was paused for handover. Everything a new developer needs: what the product is, what exists, what was decided, what is half-done, and how to continue. Read this first, then the spec, then the plans.

## Brand preview continuation — 2026-09-05

Branding corrections are complete on branch `codex/brand-preview`: native violet C/sparkle icon matches the website, one renderer supplies runtime and packaged icons, light-mode accents/selection fills are violet, and the sidebar uses the shared planned $10 price. Website header and hero share one lavender Download ClearDisk control. Palette/usage: `website/docs/BRANDING.md`.

Fresh artifact: `dist/ClearDisk.dmg`, ClearDisk **0.1.1 preview, build 2**, macOS 15+, Intel and Apple silicon, 2,787,215 bytes. SHA-256: `c018a7284dca81640d84d3c9af5809d166968a39009e133acaad956ec24c6396`. App and DMG are signed, Apple-notarized and stapled; Gatekeeper accepts the installer. The website serves the identical binary. Previous generated distribution was preserved at `/tmp/cleardisk-before-brand-preview`.

Validation: 17 Swift tests, 12 website tests, typecheck, lint, build, 12-route SEO HTTP checks, matching header/hero labels/classes, served DMG hash, native welcome-screen visual/accessibility inspection, and website header/hero visual inspection. Independent final review found no blockers. Website source `db2c620413185dd49518bb504d1b23edd538bbfd` is privately published as Sites version 4 at https://cleardisk-mac.anilgautam1180.chatgpt.site (noindex).

**This is not the completed 1.0 release.** Worker Tasks 2–8, native Plans 02–04 (licensing/removal, dark appearance, two-pass scanning), production checkout/recovery and public launch remain pending as below. Plan 02 must reuse the new `Sources/ClearDiskApp/Pricing.swift` enum rather than redeclare it. The preview explicitly has no license activation.

## 0. SEO-first continuation — 2026-09-05 (supersedes status below)

The owner made organic SEO the highest website priority and supplied a shared ChatGPT research conversation. Read the new [research and evidence assessment](seo/2026-09-05-research.md), [91-keyword candidate map](seo/keyword-map.csv), [SEO design](superpowers/specs/2026-09-05-cleardisk-seo-design.md), and [executable website-phase plan](superpowers/plans/2026-09-05-cleardisk-seo-foundation.md).

**Scaffold review closed:** Plan 01 Task 1 was independently reviewed. One P2 was found: static assets could intercept browser-navigation requests under /api/*. Fixed with run_worker_first: ["/api/*"] and a failing-then-passing configuration regression test. Fix committed as **53af895** in the existing worktree. Review after fix approved Task 1. Tests: one configuration test plus two Worker tests; typecheck passes. Actual Wrangler requests verify health JSON 200, unknown API JSON 404, and unknown page HTML 404, both ordinary and navigation requests. The existing ignored ledger records this. **Next Worker task remains Plan 01 Task 2; Tasks 2–8 are not implemented.** No merge or worktree deletion performed.

**Page ownership resolved:** Keep website/ as the single page source and preserve ThreeUI design. web/ remains the sole production /api/* owner. The first SEO phase adds a guide directory, five focused articles, metadata, structured data, sitemap/robots, and home positioning. Its private Sites preview remains noindex. Test-only checkout remains until the production Worker is ready.

**Production architecture preserved:** one cleardisk.app Worker with generated static assets plus licensing API. Vinext static export needs its own integration gate; current server-side thanks query handling and test API routes must be replaced/excluded. Do not assume the Sites build can be copied unchanged into web/public. Do not switch to live Stripe keys before fulfillment.

**Research correction:** the old keyword-cluster totals are estimates, not validated current data. The shared chat's 14K-US cache phrase is visible in Ahrefs' July 2025 snapshot, not current September 2026 evidence. The candidate CSV keeps other volumes blank. Google Ads competition measures advertisers, not organic difficulty. Numeric/model variants share one strong page; iCloud/RAM queries do not become unsupported ClearDisk features.

**Website-phase result:** implemented and privately published at https://cleardisk-mac.anilgautam1180.chatgpt.site/guides (noindex). Website branch codex/seo-foundation, commits 221b308, 7630165, f65d6e9. Verification: 12 unit tests, typecheck, lint, build, and initial-HTML route checks; local production-mode sitemap/indexing also checked before restoring preview mode. Independent review had no blockers; minor date and snapshot-count copy observations fixed. No browser interaction QA was performed.

**Remaining handover work:** finish Worker Tasks 2–8, native Plans 02–04, seven P2 guide topics, embedded checkout/recovery and single-Worker integration, verified 1.0 DMG, live fulfillment checks, then public indexing/Search Console. Stripe Tax remains undecided. Google Ads and the App Store release are deferred. The old sections below are the historical handover; these continuation decisions take precedence.

## 1. The product in one paragraph

ClearDisk is a native macOS 15+ disk-space analyzer and cleaner (Swift 6 / SwiftUI, Swift Package, no Xcode project yet). Scanning is free forever; every removal action (Trash, Delete forever, Clean Safely, Empty Trash) unlocks with a **$10 one-time license** bought on **cleardisk.app** through Stripe. The marketing wedge is Apple's opaque **"System Data"** storage category: the hero screen opens it into plain-English rows labeled Safe / Review / Leave it. Deletion is Trash-first with Undo; permanent deletion only after an explicit "No, keep it"-default confirmation. The app never uploads anything; the only network call is license activation.

Naming history is closed, do not reopen: DissectMac is a competitor; "MacClear" was chosen then renamed to **ClearDisk** (one letter from iMobie's MacClean, blends into the CleanMyMac name soup, risks Apple's Mac-prefix rule). Keyword phrases go in domains and the App Store subtitle, never the app name. Bundle id `app.cleardisk.ClearDisk`. Owner's Apple Developer team: `CH96562777`.

## 2. Where everything is

| What | Where |
|---|---|
| App source (Swift package) | `/Users/mac/hdcopy/personal/mac-clear` — `Sources/Core` (engine, no UI), `Sources/ClearDiskApp` (SwiftUI), `Sources/scan-cli` (engine harness), `Tests/CoreTests` |
| Release scripts | `Scripts/make-app.sh` (bundle + sign, with the removeItem safety gate), `Scripts/release-direct.sh` (notarize + staple + signed DMG), `Scripts/Info.plist`, `Scripts/render-icon.swift`, `Scripts/AppIcon.icns` |
| Approved design spec (binding) | `docs/superpowers/specs/2026-09-05-cleardisk-1.0-production-design.md` |
| Implementation plans (6 files) | `docs/superpowers/plans/2026-09-05-cleardisk-1.0-0{0..5}-*.md` |
| License Worker (in progress) | branch `worktree-cleardisk-1.0`, checked out at `.claude/worktrees/cleardisk-1.0`, folder `web/` |
| SDD execution ledger for plan 01 | `.claude/worktrees/cleardisk-1.0/.superpowers/sdd/2026-09-05-cleardisk-1.0-01-license-worker/progress.md` (git-ignored; its content is reproduced in section 8) |
| Second website project (separate git repo, built in parallel by another session) | `website/` inside the main checkout — see section 7 |
| Design canvas (visual mockups, published artifact) | https://claude.ai/code/artifact/f0ce990a-9adb-426a-ab58-27fdb471d5a3 (source HTML in `design/`) |
| Original build plan with keyword research | `/Users/mac/.claude/plans/i-want-to-build-sorted-dream.md` |
| Direct-download builds | `dist/` (git-ignored) — last build 0.1.0 universal, notarized |

Git on `main` (all committed, working tree clean):
```
8f804f4 Scripts: universal binary, timestamped signing, signed DMG for notarization
bafd8e2 Plans: ClearDisk 1.0 implementation plans
8b42b94 Spec: ClearDisk 1.0 production release design
992bce9 Landing page: add "Notarized by Apple" trust badge
df3234e In-app review workflow, permanent delete, live updates, UX polish
a481062 Initial commit
```
Untracked in this repo on purpose: `website/` (its own git repository) and `.claude/` (local session settings plus the worktree directory). Add `.claude/worktrees/` and `website/` to `.gitignore` if they should stay out of `git status`.

Branch `worktree-cleardisk-1.0` = main + 3 commits (`3fd8fc0`, `31f3ba3`, `58887cc`), all in `web/`. It fast-forwards onto main cleanly: from the main checkout, `git merge --ff-only worktree-cleardisk-1.0` (after this handover commit it becomes a normal merge with no conflicts). Remove the worktree afterwards with `git worktree remove .claude/worktrees/cleardisk-1.0`.

## 3. What exists and works today

**App (0.1.0, runs, 17 tests green):**
- Scan engine: `getattrlistbulk`-based (`BulkScanner`), parallel work queue (`ParallelScan`), du-exact on fixtures, hardlink dedup, symlinks not followed, allocated sizes. Benchmarked ~6M files / 36 s on an M-series Mac; on a slow Intel Mac a home scan can take ~5 minutes (plan 04 fixes the perceived speed).
- Screens: Welcome, Scanning, System Data (hero), Dev Junk (`DevJunkScan`), Categories, Browse, Treemap (`Squarify`), Large Files, Search. Sidebar with volume donut, FDA (Full Disk Access) hint, Trash card, Rescan.
- Removal: `TrashService` is the only place that removes files (`trashItem`, `trashContents`, `deleteForever`, `restore`), behind a deny-by-default blocklist (`verdict(forTrashing:)`). `make-app.sh` fails the build if `FileManager.removeItem` appears anywhere else. `TreeSurgery` patches the in-memory tree after removals so the UI updates without a rescan; toast with Undo.
- Not yet: licensing, dark mode (palette is hard-coded light hex), unified confirmation (permanent delete still asks you to type the file name), purge-from-Trash, result feedback, two-pass scan.

**License Worker (`web/` on the branch, plan 01 Task 1 of 8 done, NOT reviewed):**
- Scaffold: `package.json`, `tsconfig.json`, `wrangler.jsonc` (assets, KV `LICENSES`, `send_email` binding `EMAIL`, vars), `vitest.config.ts` (current `cloudflareTest()` plugin API, inline bindings), `src/env.ts`, `src/index.ts` (router with `GET /api/health`), `public/404.html`, `test/health.test.ts`.
- `npm test` 2/2, `npm run typecheck` clean, `npm audit` 0. Versions: wrangler 4.129.0, vitest 4.1.11, @cloudflare/vitest-pool-workers 0.22.0, stripe 22.6.1, workers-types 5.20260904.1, TypeScript 5.9.3. `compatibility_date` 2026-08-15 in both configs (the pool's bundled workerd ceiling; a later date throws `ERR_FUTURE_COMPATIBILITY_DATE`).
- Install quirk: `cd web && npm install --legacy-peer-deps` (plain install hits an npm 10.9.2 arborist bug unrelated to this graph; npm 12 blocks workerd's postinstall, which is worse).

## 4. Decisions that are locked (from the approved spec, section 2)

| Topic | Decision |
|---|---|
| Distribution | Direct download first (notarized DMG). Mac App Store edition is a **later, separate spec** (sandbox, StoreKit at the $9.99 tier, no external buy link, no update check, no `tmutil`). |
| Payment | Stripe **embedded Checkout** on cleardisk.app/buy-now, $10 USD one-time. Stripe Tax is a config toggle (`AUTOMATIC_TAX`). Not Lemon Squeezy (earlier plan superseded). |
| License model | Short key `CLDK-XXXX-XXXX-XXXX-XXXX` (Crockford base32, HMAC of the Stripe session id, so re-issuing is idempotent). Online activation once via a Cloudflare Worker + KV; the Worker returns an **Ed25519-signed receipt** that the app verifies offline on every launch. Weekly silent recheck; only "revoked"/"unknown" drops the license. |
| Activations | 3 Macs per key (hardware UUID). Support frees slots by editing KV. |
| Refunds | 30-day money-back; full refund or dispute webhook revokes the key. |
| Email | Key emails from `hello@cleardisk.app` via Cloudflare Email Sending (`send_email` binding). |
| Deep link | `cleardisk://activate?key=…` from the thank-you page and the email; app activates without typing. |
| Price display | "$10" everywhere (one constant `Pricing.display` in the app). Never "$9.99" outside the App Store. |
| Dark mode | Adaptive palette (light/dark pairs in `UI.swift`), follows System Settings, Settings window offers System/Light/Dark. Build guard forbids raw color literals outside `UI.swift`. |
| Removal UX | One `RemovalSheet` for everything: impact block, free-space before/after, "Also remove from Trash now" checkbox (remembered), result view with the number freed and Undo. Reversible → "Move to Trash" is default; irreversible → "No, keep it" is default, Return/Escape keep, red "Yes, delete" needs a click. Type-the-name confirmation removed. |
| Scan | Two-pass home scan: `~/Library` + dot-folders first (System Data screen appears fast), the rest grafts on in the background; live per-bucket counters ("Caches 3.2 GB…") while scanning; `tmutil` off the main thread. |
| Domain / hosting | cleardisk.app is bought and on Cloudflare DNS. One Worker serves the site as static assets plus `/api/*`. |

## 5. Architecture the plans build toward

- **App**: `AppState` (`@MainActor @Observable`) owns scan state, the removal routing (`requestRemoval` is the single gate), and a `LicenseStore`. `RemovalRequest` (items with one or more paths, mode trash/forever) → `RemovalExecutor` (runs off main through `TrashService`) → `RemovalOutcome` → `applyRemoval` + result view. `LicenseStore` reads `~/Library/Application Support/ClearDisk/license.json` (0600) and verifies the receipt with the embedded public key (`LicensePublicKey.swift`, generated by `web/scripts/gen-signing-key.mjs`).
- **Worker** (`web/src/*.ts`): `keys.ts` (derive/normalize), `receipt.ts` (Ed25519 via WebCrypto), `store.ts` (KV records `key:`, `email:`, `pi:`, `session:`), `email.ts`, `activate.ts` (`POST /api/activate` 200/400/403/404/409, `POST /api/recover` always 200), `stripe.ts` (`POST /api/checkout` embedded session, `POST /api/stripe/webhook`, `GET /api/key?session_id=`), `index.ts` router + assets fallback. Secrets: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `KEY_SECRET`, `LICENSE_SIGNING_KEY`. Rate limiting is a Cloudflare WAF rule on `/api/*`.
- **Website**: see section 7 (two candidates).

Full detail with exact signatures, KV schema, status codes and copy: the spec sections 4–10 and the plans.

## 6. Build, run, test, release

```bash
# App
swift test                          # Core tests (17). Plan 02 adds a ClearDiskAppTests target.
swift run -c release ClearDiskApp   # dev run (not a bundle: no URL scheme, FDA relaunch disabled)
./Scripts/make-app.sh               # dist/ClearDisk.app, universal, signed (Developer ID > Apple Development > ad-hoc)
./Scripts/release-direct.sh         # notarize (keychain profile "csvcompare", shared with the CSV Compare Local product), staple, signed DMG
swift run -c release scan-cli ~     # engine benchmark

# Worker
cd web && npm install --legacy-peer-deps && npm test && npm run typecheck
npm run dev                         # http://localhost:8787 ; secrets in web/.dev.vars (git-ignored)
npm run deploy                      # after provisioning (plan 01 Task 8)

# App against a local Worker
CLEARDISK_API=http://localhost:8787 swift run -c release ClearDiskApp   # supported once plan 02 Task 5 lands
```
Signing prerequisites on the machine: a "Developer ID Application" certificate in the keychain and `xcrun notarytool store-credentials csvcompare --apple-id <id> --team-id CH96562777`.

## 7. The two website efforts — reconcile before plan 05

Two things exist and overlap:

1. **`web/public/` pages, planned in plan 05** (plain HTML, same palette as the app, buy-now with embedded Checkout, thanks polling `/api/key`, recover, download, three SEO pages, privacy, terms, robots, sitemap). Only `404.html` exists so far. Plan 05 has the full page markup and copy.
2. **`website/`** in the main checkout — a **separate git repository** (its own `.git`), built in parallel by another session on 2026-09-05 around 02:30: a design-forward React/vinext site (near-black canvas, lavender accent, ThreeUI horizon shader, interactive demo) with routes `/`, `/buy-now`, `/download`, `/thanks`, `/privacy`, `/terms` and its own `app/api/checkout` + `checkout-status` routes using a hosted Stripe test checkout. Its `docs/HANDOFF.md` says it expects to integrate this repo's `web/` license Worker for webhooks, issuance, receipts, email and refunds, and that its bundled DMG is the old 0.1.0 build. A `wrangler dev`/workerd process from that folder may still be running (`pgrep -fl workerd`).

Recommendation: keep **one** owner per concern. `web/` (this repo, plan 01) owns everything under `/api/*`, the KV records, emails and receipts. Pick one of the two sites for the pages; if `website/` wins, drop its `app/api/checkout*` routes in favor of `POST /api/checkout` and `GET /api/key` from the Worker, and make its thank-you page call `/api/key?session_id=` and link `cleardisk://activate?key=…`. If it is hosted separately from the Worker, put the Worker on `api.cleardisk.app` and set the app's base URL accordingly (`LicenseClient.baseURL`, plan 02). Plan 05's SEO copy and checklist stay useful either way.

## 8. Execution state of the plans and how to continue

The plans were being executed with the "subagent-driven development" workflow: one task at a time, a task review after each, a ledger in `.superpowers/sdd/…/progress.md`. You can continue that way or just work through the tasks by hand — each task lists files, code, tests, commands and a commit.

| Plan | Status |
|---|---|
| 01 License Worker (8 tasks) | Task 1 implemented on the branch (`3fd8fc0..58887cc`), **task review not run**. Tasks 2–8 not started. Task 8 needs the owner's Cloudflare and Stripe logins. |
| 02 Removal flow + in-app licensing (7 tasks) | Not started. Needs the public key from `node web/scripts/gen-signing-key.mjs` (plan 01 Task 3) pasted into `Sources/ClearDiskApp/LicensePublicKey.swift`. |
| 03 Dark mode + polish (4 tasks) | Not started. Must run after 02 (it restyles a button 02 moves). |
| 04 Two-pass scan (4 tasks) | Not started. |
| 05 Website + go-live (4 tasks) | Not started; reconcile section 7 first. |
| Mac App Store edition | Deferred; needs its own spec (notes in spec section 10.2). |

Ledger for plan 01 (verbatim rulings, so nothing is lost if the worktree is deleted):
- Pre-flight scan of plan 01 found no conflicts between tasks.
- Ruling: `compatibility_date` may be lowered to the newest date the installed workerd accepts (plan wrote "2026-09-01" blind). Result: 2026-08-15 in both configs.
- Ruling: package version ranges in the plan are starting points; bump to the latest mutually compatible versions.
- Ruling: use the current `@cloudflare/vitest-pool-workers` (0.22.x, vitest 4.1, `cloudflareTest()` Vite plugin, types from `@cloudflare/vitest-pool-workers/types`) instead of pinning 0.12.21 to keep the plan's config text verbatim; same semantics (inline bindings, `main`, KV). Reason: every later task's tests run in this pool; the old pool carried 6 high audit findings.
- Ruling: align `wrangler.jsonc`'s date with the pool's (2026-08-15). Done in `58887cc`.
- Task 1 stopped before review at the owner's request. Next step: review `8f804f4..58887cc` against plan 01 Task 1 + Global Constraints, then Task 2.

Plan-level notes that matter when you continue:
- The plan's `vitest.config.ts` text is outdated (old `defineWorkersConfig` API); the committed file on the branch is the correct one. Everything else in plan 01 Tasks 2–8 is unaffected.
- The `EMAIL` binding is never emulated in tests; handlers take `(request, env)` and tests inject a fake `EMAIL` via `test/helpers.ts` (plan 01 Task 4).
- The Stripe webhook must be verified with `stripeClient(env).webhooks.constructEventAsync(..., Stripe.createSubtleCryptoProvider())` on Workers.
- SPM can test the executable target (`ClearDiskAppTests` depends on `ClearDiskApp`); the app target is a plain executable with `@main`.
- Keep `FileManager.removeItem` inside `Sources/Core/TrashService.swift` only; the license file is cleared by overwriting, never removed.
- After plan 03, `Color(hex:` and `background(.white` may appear only in `UI.swift` (second build guard).

## 9. Accounts, secrets and one-time provisioning (owner)

- **Apple**: Developer Program member, team `CH96562777`; Developer ID Application cert; notary keychain profile `csvcompare`. App Store Connect record not created yet.
- **Cloudflare**: cleardisk.app on Cloudflare DNS. To do (plan 01 Task 8): `wrangler login`, `wrangler kv namespace create LICENSES` (paste id into `wrangler.jsonc`), `wrangler email sending enable cleardisk.app` + the SPF/DKIM/DMARC records it prints, secrets via `wrangler secret put`, custom-domain route, WAF rate-limit rule on `/api/*` (20/min/IP), Web Analytics with automatic setup.
- **Stripe**: product "ClearDisk lifetime license", one-time price $10 USD (test mode first, live at go-live); webhook endpoint `https://cleardisk.app/api/stripe/webhook` for `checkout.session.completed`, `charge.refunded`, `charge.dispute.created`; publishable key into the site config; Stripe CLI for local webhook forwarding.
- **Keys to generate once**: `node web/scripts/gen-signing-key.mjs` (plan 01 Task 3) prints `LICENSE_SIGNING_KEY` (Worker secret, never committed) and the raw public key for the app. `KEY_SECRET` = any long random string (`openssl rand -base64 48`).
- **Google Ads**: conversion tag goes only on the thank-you page (plan 05 Task 4 Step 6).
- Other domains verified available earlier, not bought: macstoragefull.com/.app, clearsystemdataonmac.app (redirect/problem pages).

## 10. Marketing and SEO context (owner is a web dev, self-described weak at SEO; wants search-driven acquisition, no influencer marketing)

- Wedge: "System Data" + "mac storage full" error-message queries (lowest competition, exact product fit; purchase intent highest on error terms). Keyword clusters from the research (US monthly): cache clearing 70–130k, RAM 60k+, uninstall 30–70k, cleaner-seeking 35–55k, free-up-space 25–50k, System Data 25–50k, analyzer 1–12k. Head terms are MacPaw's; win long-tail problem pages.
- Site H1: "Clear System Data on Mac". First problem pages: `/clear-system-data-on-mac`, `/mac-storage-full`, `/what-is-system-data-on-mac` (draft copy in plan 05 Task 3). A Keyword Planner export from the owner was pending to validate the next pages.
- App Store listing (later): name "ClearDisk", subtitle "Fix storage full — clear System Data & caches", privacy label "Data not collected". Expect one rejection cycle; copy must say "see what's using space", never "boost".
- Conversion patterns adopted from CleanShot X / DaisyDisk / Bartender / Downie: free download before the paywall, one price stated as one-time and anchored against CleanMyMac's yearly fee, 30-day guarantee, "Is it safe?" FAQ, notarized badge, no account, sticky mobile CTA, in-app paywall at the moment of value ("Reclaim 23.4 GB — unlock for $10").

## 11. Known limits and risks

- Hardlinks shared across the two scan passes count twice (accepted, ponytail comment in the plan).
- One directory is one work item: a single directory with hundreds of thousands of files enumerates serially (`getattrlistbulk` limitation).
- `SystemDataScan.build` currently shells out to `tmutil` on the main thread (plan 04 Task 3 fixes it).
- Full Disk Access is detected by probing TCC-protected paths; the relaunch button only works from the bundled app.
- Cleaner apps get close App Review scrutiny; the sandboxed edition cannot use license keys, `tmutil`, or external buy links.
- The `dist/` DMG on the old `website/` project is 0.1.0; never ship it as 1.0.
- Windows/Linux: none. macOS 14 and below: unsupported (Package platform is macOS 15).

## 12. Open questions for the owner

1. Which website to keep (section 7), and where the Worker lives relative to it.
2. Stripe Tax on or off at launch (`AUTOMATIC_TAX`).
3. Google Ads conversion id.
4. When to start the Mac App Store edition (after direct 1.0 ships is the plan).

Contact for product questions: the owner (anilgautam1180@gmail.com). Support address for customers: hello@cleardisk.app.


## Continuation — experience, typography, access setup (5 September 2026)

Owner requested awesome-design-md + UI UX Pro Max for native/website design, treemap loading and animation. Then requested Apple-style reading typography using plugin87/ux-ui-agent-skills, and fewer permission interruptions with a Scan my disk action. Talivia was explicitly paused until after launch: no tracker, service or analytics dependency added.

### Native changes and installer

Native branch codex/brand-preview includes 5e4a929, 7d1b65d, 30f7ce1, bbb702e and edf4f0a. Graphite semantic surfaces, compact disk summary, redesigned welcome/scanning states, native system typography, readable dark treemap colours. Initial derived reports build on the worker before publishing the tree. Treemap geometry uses immutable bounded snapshots, detached work, cancellation and stale-result guards; immediate skeleton/loading and empty state. Progress reports measured files/bytes and real stages, not a fabricated percentage; Reduce Motion is respected. Existing deletion safeguards unchanged.

Scan my disk targets the root through a central access gate. Before access is confirmed, an inline setup page points to System Settings → Privacy & Security → Full Disk Access. Checking/returning from Settings does not start scanning. Explicit folder choice remains. Old Safari enumeration probe replaced with a conservative read-only open of protected TCC.db paths (no contents read/queried). Apple provides no public FDA status API, so a false negative is possible and additional macOS/iCloud restrictions/prompts cannot be ruled out. Relaunch closes the old instance only on success and is disabled while pending.

Final release: 0.1.3 build4, macOS15+, universal x86_64/arm64, Developer ID team CH96562777. App and DMG notarized/stapled; strict codesign and Gatekeeper checks pass. dist/ClearDisk.dmg and versioned alias dist/ClearDisk-0.1.3.dmg are identical: 2,999,122 bytes; SHA-256 bf00af0bb97d883be8f4cd9968e5c0634ac2b91176384734853fb866afc4b875. Same binary copied to website/public/ClearDisk.dmg. Native source through edf4f0a plus Info.plist 0.1.3/build4. Release log /tmp/cleardisk-apple-access-release-verified.log. Older0.1.2 package was superseded before publishing.

Validation: 25 Swift tests pass; debug and universal release builds pass. Independent code review found no blocker; contrast and repeat-relaunch issues corrected. Native isolated UI QA verified welcome, Scan my disk → inline access, repeated check and Back at 1100×752 without granting OS permissions. Earlier QA completed a real home scan and treemap drill-down/back; no files removed. Access-granted Settings/relaunch transitions were code-reviewed but not live-tested by changing OS permissions. Temporary QA apps are not release deliverables.

Remaining native limitations: no public FDA status API; explicit graphite appearance (automatic theme/settings still pending); initial bounded map snapshot and post-delete derived updates remain main-isolated; no end-to-end speed benchmark; low-level scan cancellation and full two-pass scan remain follow-up work.

### Website current design and verification

website/ remains a separate repository, sole page owner. Approved future web/ Worker remains sole production /api/* owner. Website source commit98ac3329564acd7d27d5cdfcc62fd94d59b5e6eb is pushed to existing Sites source main. Pale reading surfaces and centered product hero supersede earlier all-dark/split hero. Native system font stack replaces Geist, body17–21px and guide text19px, controlled600-weight headings, consistent violet download pills. Dark demonstration tokens explicitly scoped. Supplied plugin87 Apple reference and typography tokens used; see website/docs/DESIGN.md and BRANDING.md. No paid font purchased/bundled; no callable MyFonts tool available.

Storage scan illustration remains labelled example data and only animates on request. Page entrance motion is progressive enhancement over visible SSR content and respects Reduce Motion. Background shader no longer mounted; attributed ThreeUI source retained. Five guides, metadata/schema, internal links, and test-only checkout remain. Private preview stays noindex with empty sitemap. Download page now matches Scan my disk/access flow and0.1.3 binary.

12 website unit tests, typecheck, lint, build and compiled HTTP checks passed. HTTP checks cover12 HTML routes, metadata, articles, related links,404, robots/sitemap and download. Served DMG SHA matches exact native artifact. New key contrast pairs verified: body7.52:1, muted5.79:1, white action text6.61:1, guide body10.01:1. Static design review confirmed scope/cascade; fixed mobile CTA specificity. Browser UI QA was not requested or performed.

Design tools installed by explicit owner request: Product Design, Frontend Design Premium, Figma enabled in Codex; UI UX Pro Max and Frontend Design local skills installed. Figma account access not exercised. Repository references stored under docs/design-references.

This does not complete the original1.0 plans: Worker licensing/fulfillment tasks2–8, native activation/final removal flow, two-pass scanning, automatic appearance preferences, production live checkout, support inbox/domain/Search Console and public launch remain. Keep the original ledger and Claude worktree intact. Do not enable live Stripe merely because design work is finished. Talivia stays paused.


Private publish succeeded: https://cleardisk-mac.anilgautam1180.chatgpt.site (owner-only access rechecked, one owner, no groups/external visitors). Sites version5 from exact source98ac3329564acd7d27d5cdfcc62fd94d59b5e6eb; version ID appgprj_6a9b31a08f1081919bd18fe3e2633559~appgver_7ac07584e7088191b06da1d789d907a4; deployment appgdep_6a9b416c52288191b3f01a4f56e88cea, succeeded, environment revision2. No public access/indexing or live billing enabled.
