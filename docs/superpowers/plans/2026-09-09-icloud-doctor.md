# iCloud Doctor implementation plan

Approved by owner 2026-09-09: implement the integration, update the software and articles, and add Search Console under the existing anilgautamwork account when accessible.

**Spec:** ../specs/2026-09-09-icloud-doctor-integration.md
**Architecture:** A repository-local Foundation module supplies scanner, history and safe file actions; ClearDisk owns UI and licensing. The separate website repository owns pages, downloads and its current Worker.

## Tasks

- [x] Engine: vendor the existing SyncDoctor core; correct classification, cancellation/materialization safeguards and consecutive history; add verified archives and operation policies. Test using disposable local fixtures, never remove real user files. Deliver public interfaces to the UI implementer.
- [x] Native UI: add independent iCloud Doctor navigation, scan/progress/cancel and accessible result states; storage filters, history, raw metadata, safe confirmed actions and license gates. Keep Finder responsible for deleting cloud originals.
- [x] Website: add eight distinct, source-checked iCloud guides, dedicated product page, internal links and sitemap entries. Preserve current branding, checkout and analytics. Mark features unavailable until the release artifact is verified.
- [x] Review: independently inspect engine and UI safety, fix blockers, run Swift tests/build, verify native UI. Run website tests/typecheck/lint/build and desktop/narrow browser checks.
- [x] Release: build universal signed/notarized 1.1.0, preserve existing artifacts, verify hash/signatures; publish app release and deploy matching website content and download.
- [x] Search Console: inspect existing bgclear account access, add cleardisk.app under anilgautamwork when possible, verify ownership through the existing Cloudflare zone or site verification and submit sitemap. Report real status, never imply indexing is guaranteed.

## Execution ledger

- Baseline: app HEAD 460e1c5; 47 Swift tests passing; SyncDoctor prototype 6 tests passing. Existing unrelated .claude/ and nested website/ remain untouched by parent commits.
- Ruling: reuse the user's current checkout/license configuration rather than outdated test-mode handover text; changing payment mode is outside this feature release.
- Ruling: approved archive flow leaves cloud originals for explicit Finder review. No bypass of ClearDisk's cloud-folder deletion protections.
- Ruling: implement in the current clean tracked checkout on a codex feature branch, preserving the nested website repository and existing local signing configuration.

- Completed: engine8fb50c7/a2b039e, UI db99922/238a2ae, release bfba65a/tagv1.1.0, initial website content b07f35c and artifact9fc42d1.63Swift/42website tests and69liveHTML checks pass. Google HTTPS property verified and sitemap processed64URLs. Native real cloud mutations remain untested; fixtures and read-only UI QA only.
