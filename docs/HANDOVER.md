# ClearDisk — Developer Handover

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
