# ClearDisk SEO-first website design

## Goal and scope

Organic search is the primary acquisition channel. Preserve the existing ThreeUI product design while adding focused, useful, crawlable problem guides and accurate metadata. The user requested a plan before implementation and research from the shared chat and current web.

This extends the approved production design and replaces Plan 05's plain-HTML page implementation approach. It does not change the product name, $10 price, macOS 15+ floor, safety design, licensing model or native Plans 02–04.

First executable website phase: technical SEO, guide directory, five P1 guides, home positioning, and preview verification. Further content and production integration follow as distinct milestones. Native licensing, dark mode and two-pass scanning remain in their existing plans.

## Architecture decision

- website/ remains the sole page-source repository and preserves its React/Vinext, Shadcn and ThreeUI work.
- web/ in the existing license worktree remains the sole future production /api/* owner. Do not create a second webhook/license store in website/.
- Current hosted Stripe test routes remain clearly test-only until their replacement is ready; do not switch live keys.
- Production target remains one cleardisk.app Worker serving exported site assets and the licensing router. Vinext beta.9 contains static-export support, but the export must pass a dedicated integration gate: current server-side thanks searchParams and API routes cannot simply be exported.
- Keep private Sites preview for design/content review. Preview is noindex, independent of eventual production indexing. No domain migration or live billing is performed by the first SEO phase.

## Page and content contract

One guide registry defines slug, title, description, intent, summary, dated editorial review, ordered sections, related guide slugs and source links. The server route resolves only known published slugs and returns 404 otherwise. A guide directory, navigation links, metadata and sitemap derive from this same registry.

Five initial slugs: clear-system-data-on-mac; what-is-system-data-on-mac; system-data-too-large; system-data-keeps-growing; mac-storage-full. Their briefs and prioritized successor pages are in docs/seo/2026-09-05-research.md. Group numeric/model variants into the appropriate existing article.

Article layout: breadcrumb, eyebrow, one H1, direct answer, editorial date/publisher, table of contents, readable sections, relevant related guides, references and free-download CTA. All content and links appear in the initial HTML. No article depends on the homepage shader or interactive demo. Mobile reading remains comfortable and controls retain visible focus.

Home H1: Clear System Data on Mac. Supporting copy explains what is using storage, what to review and local scanning. Keep the existing visual composition and demonstration explicitly marked as example data. Distinguish the product page from the full manual how-to guide.

## Truth and indexability

ClearDisk is a native macOS 15+ app. Scanning is free; the $10 one-time cleanup license covers three Macs and all 1.x updates at launch. Current binary is a 0.1.0 preview. Never promise live checkout/activation until fulfilled end to end.

No fake rankings, testimonials, authors, review scores, reclaimed-space totals or measured keyword volumes. Do not describe all System Data as disposable. Trash does not immediately free storage. Snapshot storage is separately reported and macOS managed. Browser examples cannot inspect visitors' disks.

Preview defaults to noindex. Production requires an explicit flag and canonical https://cleardisk.app. Sitemap contains only indexable public routes; exclude purchase return, recovery and API routes. Guides use self-canonicals, Article/BreadcrumbList markup and real publication dates. Unknown routes return 404. FAQs need no rich-result promise.

## Evidence and success criteria

Source research: docs/seo/2026-09-05-research.md and docs/seo/keyword-map.csv. Volumes remain unknown except the dated historical Ahrefs estimate. No additional marketing plugin is required.

Acceptance: tests prove canonical/indexing policy and guide discovery; HTTP checks show full article content and metadata without executing JavaScript; build, lint and typecheck pass. Private preview shows completed content. Production launch separately verifies asset/API ownership, public indexing, sitemap, licensed 1.0 DMG, fulfillment and activation/refund behavior.

No SEO outcome is guaranteed. After production launch use Search Console's actual non-brand query/page data and aggregated download/purchase counts to refine pages.
