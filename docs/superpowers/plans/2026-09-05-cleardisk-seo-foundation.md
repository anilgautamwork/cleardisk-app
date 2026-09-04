# ClearDisk SEO foundation implementation plan

> **For agentic workers:** Execute task-by-task with Superpowers verification and code review. The Site-owning agent implements website/ changes; reviewers may review but must not edit the Site checkout.

**Goal:** Turn the existing ClearDisk product website into a crawlable, useful multi-page site with five focused storage guides.

**Architecture:** Preserve website/ as the page source. Use a typed guide registry, server-rendered article routes, shared metadata helpers and a generated sitemap. web/ remains production API owner; this phase retains clearly labeled test checkout until the licensing milestone is ready.

**Tech Stack:** Existing React 19.2.8, Vinext 1.0.0-beta.9, TypeScript 5.9.3, Shadcn, CSS, native Node tests and Cloudflare/Sites preview.

**Spec:** docs/superpowers/specs/2026-09-05-cleardisk-seo-design.md. Research: docs/seo/2026-09-05-research.md.

## Global Constraints

- Name ClearDisk; canonical production domain https://cleardisk.app; macOS 15+.
- $10 once, three Macs, all 1.x updates at launch. Current binary 0.1.0 preview.
- No real payments until license fulfillment is working.
- No fake testimonials, authors, benchmarks, volume or keyword-difficulty metrics.
- Preview defaults noindex; only explicit production configuration enables indexing.
- Do not modify native Swift sources in this website phase.
- Preserve ThreeUI attribution and reduced-motion behavior.
- web/ is the sole production /api/* owner. Reserve those paths for Worker execution.
- Test meaningful behavior; verify initial HTTP HTML rather than assuming client rendering is sufficient.
- Keep secrets in ignored local files or platform secret storage, never in source or plan.
- Commit each independently verified task in its owning repository.

## Task 1: Close the handover scaffold review

**Files:** existing worktree web/wrangler.jsonc, web/package.json; create web/test/config.test.mjs; update existing worktree ledger and parent docs/HANDOVER.md.

**Interface:** existing GET /api/health continues to return JSON; static assets may never intercept /api/*.

- [x] Review 8f804f4..58887cc against Plan 01 Task 1 and ledger rulings. Reviewer reports one P2: assets intercept navigation API requests.
- [x] Add Node regression test:
    import assert from 'node:assert/strict';
    import { readFileSync } from 'node:fs';
    import { test } from 'node:test';
    test('API requests always reach the Worker', () => {
      const config = JSON.parse(readFileSync(new URL('../wrangler.jsonc', import.meta.url), 'utf8'));
      assert.ok(config.assets.run_worker_first.includes('/api/*'));
    });
- [x] Run node --test test/config.test.mjs from web; observe failure before changing config.
- [x] Add assets.run_worker_first = ["/api/*"]. Add test:config script and make npm test run it before vitest run.
- [x] Run npm test and npm run typecheck; verify actual Wrangler navigation request with Sec-Fetch-Mode: navigate receives health JSON and unknown API JSON 404, while unknown page remains HTML 404.
- [x] Record review/fix evidence in ledger, then commit only task files.

## Task 2: Shared indexing policy and content model

**Files in website/:** create lib/seo.ts, lib/guides.ts, test/seo.test.ts; modify app/layout.tsx and metadata exports on download, buy-now, thanks, privacy and terms pages.

**Interfaces:**
    export type GuideSection = { id: string; title: string; paragraphs: string[]; items?: string[] };
    export type Guide = {
      slug: string; title: string; description: string; summary: string;
      published: string; updated: string; sections: GuideSection[]; related: string[];
      sources: { label: string; url: string }[];
    };
    export const guides: Guide[];
    export function getGuide(slug: string): Guide | undefined;
    export const SITE_URL = 'https://cleardisk.app';
    export function canonical(path: string): string;
    export function shouldIndex(production: boolean, path: string): boolean;
    export function pageMetadata(title: string, description: string, path: string): Metadata;

- [x] Add failing Node tests for canonical('/mac-storage-full'), private noindex, transactional noindex and published guide indexing.
    assert.equal(canonical('/mac-storage-full'), 'https://cleardisk.app/mac-storage-full');
    assert.equal(shouldIndex(false, '/mac-storage-full'), false);
    assert.equal(shouldIndex(true, '/thanks'), false);
    assert.equal(shouldIndex(true, '/mac-storage-full'), true);
- [x] Implement helper. Canonical strips query/fragment, accepts root-relative local paths only. Indexing uses explicit SITE_INDEXABLE=true build setting, default false. Never infer indexing from NODE_ENV: previews also use production builds.
- [x] pageMetadata emits unique title, description, canonical, robots and matching OpenGraph URL/title/description. Root sets metadataBase, icons, language and default noindex policy.
- [x] Add five full guide records from the spec/briefs. Each gives an original diagnostic workflow, accurate product limits and relevant source links; no invented author attribution.
- [x] Tests require unique slugs, section IDs, resolvable related links, valid dates and nonempty substantive sections. Run npm test and npm run typecheck.
- [x] Commit the content model and policy.

## Task 3: Server-rendered guide experience and discovery

**Files in website/:** create app/guides/page.tsx, app/[slug]/page.tsx, components/guide-article.tsx, app/not-found.tsx; modify components/brand.tsx and app/globals.css.

**Interfaces:** route consumes getGuide(slug); article consumes Guide; metadata uses pageMetadata. Explicit static routes continue to outrank the guide slug route.

- [x] Add registry coverage checks to test/seo.test.ts for these exact slugs:
    const required = ['clear-system-data-on-mac', 'what-is-system-data-on-mac',
      'system-data-too-large', 'system-data-keeps-growing', 'mac-storage-full'];
    for (const slug of required) assert.ok(getGuide(slug));
    assert.equal(getGuide('not-a-real-guide'), undefined);
- [x] Server route uses awaited params and notFound() for unknown slug. Export generateStaticParams() returning guides.map(({slug}) => ({slug})). Export generateMetadata using each guide record.
- [x] Render breadcrumb, title/summary, date/publisher, TOC anchors, semantic sections, lists, references, related guides and download CTA. Serialize Article/BreadcrumbList JSON-LD with JSON.stringify(data).replace(/</g, '\\u003c').
- [x] Guide directory groups the five problems in readable linked cards; navigation/footer links make guides discoverable from every page. Keep article CSS separate from hero styling and avoid article client components.
- [x] Unknown page uses an actual 404, with home and guide links.
- [x] Run npm test, npm run lint, npm run typecheck and npm run build. Commit.

## Task 4: Product positioning and discovery endpoints

**Files in website/:** modify app/page.tsx; create app/robots.ts, app/sitemap.ts, scripts/check-seo.mjs; extend test/seo.test.ts.

**Interfaces:** sitemap paths derive from guides plus / and /guides and /download. Transactional and legal pages are not included. Preview sitemap returns no indexable entries.

- [x] Change home H1 to “Clear System Data on Mac.” Retain ThreeUI composition and example demo. Add links to first guides next to useful product explanations, not a keyword-stuffed paragraph.
- [x] Root/product metadata describes ClearDisk's free scanner and planned cleanup accurately. Add FAQ answer linking the definition/how-to guides.
- [x] Export sitemap in supported metadata route format. For each published page return canonical URL; dates only from real guide updated field.
- [x] robots permits crawling of public content so noindex can be read; disallow /api/ and include sitemap only for production. Never publish secrets or transactional URLs.
- [x] Tests ensure sitemap excludes /thanks, /buy-now and /api; all guide pages appear exactly once in production mode and none are advertised as indexable in preview.
- [x] Build and run HTTP smoke checks for home, directory, all guides, sitemap, robots and unknown slug. Inspect initial HTML title, canonical, robots, H1, article text, internal links and parseable JSON-LD without browser JavaScript.
- [x] Commit.

## Task 5: Review, private preview and handover

**Files:** website/docs/HANDOFF.md; parent docs/HANDOVER.md; this plan.

- [x] Request independent code review of SEO implementation against the spec; fix Important findings and rerun affected checks.
- [x] Run final npm test, npm run lint, npm run typecheck, npm run build once after final changes. HTTP checks verify preview noindex and functional existing checkout/download routes.
- [x] Use Sites hosting workflow to save/deploy the existing private Site, retaining its project ID. Verify deployment status and open preview for user.
- [x] Record exact commit IDs, completed tasks, test counts, route list and indexability state. Never mark production live or Plan 01 Tasks 2–8 complete.
- [x] Link the next production/content milestones from the handover.

## Following milestones (separate existing plans, not silently completed here)

1. Finish Plan 01 Tasks 2–7: key derivation, receipts, storage/email, activation/recovery, Stripe and router. Re-review concurrency/idempotency, receipt security and webhook retries before production.
2. Complete Plan 02 native removal/licensing, Plan 03 dark mode and Plan 04 scan improvements in their dependency order. Preserve their safety guards. Generate/handle signing keys without placing secrets in documentation.
3. Expand the guide library using the seven P2 briefs in research. Add exact UI steps only after verifying the relevant current Apple/app interfaces.
4. Reconcile Plan 05 production hosting: build a static export from website/ with a dedicated config; exclude its test API routes and move thanks query reading client-side; copy generated HTML/assets to web/public via a reproducible build. Fail if export leaves missing routes or navigation payloads. Run real Worker asset-routing checks including /api navigation.
5. Replace hosted test checkout with the approved embedded checkout; thanks polls GET /api/key, recovery calls POST /api/recover, deep link uses cleardisk://activate?key=. No client-side license issuance.
6. Provision Plan 01 Task 8, decide Stripe Tax, ship verified notarized 1.0, exercise purchase→email→activation→refund, and only then accept live payments. Use original Plan 05 release checks with the new page-source ownership.
7. Enable cleardisk.app indexing, verify Search Console, submit sitemap, review query/page performance. Google Ads and App Store release remain deferred.

## Self-review

Spec coverage: first-phase routes, truthful copy, crawlable rendering, metadata, sitemap, API ownership and private preview all map to Tasks 1–5. Native release and live billing remain explicitly separate. All content is sourced from a single registry. Unknown metrics and unimplemented release work are not presented as complete.


## Completion evidence — first website phase only

- Worker review/fix: 53af895, existing worktree branch; 1 configuration + 2 Workers tests, typecheck and actual navigation routing verified.
- Website commits: 221b308 (content/indexing), 7630165 (guide experience), f65d6e9 (discovery/positioning).
- Final website: 12 unit tests, typecheck, lint, production build and HTTP assertions passed. Both explicit indexable and default noindex builds were checked locally; restored and deployed noindex.
- Private preview: https://cleardisk-mac.anilgautam1180.chatgpt.site/guides — publication succeeded, saved version 3.
- Review: no blockers; fixed minor visible-date consistency and snapshot-count copy.
- No native Swift edits, live charges, domain migration, or public search launch. Following milestones remain pending.
