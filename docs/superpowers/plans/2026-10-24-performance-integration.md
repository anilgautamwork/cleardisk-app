# ClearDisk Performance Implementation Plan

**Goal:** Add WhySlow's existing feature set to ClearDisk.

**Architecture:** PerformanceCore contains the imported engine; PerformanceUI holds the feature screens and coordinator. ClearDisk retains app lifecycle, storage navigation, license and updater ownership.

**Tech stack:** Swift 6, SwiftUI/AppKit, macOS 15+, existing Sparkle 2.10.0.

**Spec:** ../specs/2026-10-24-performance-integration.md

## Tasks

- [x] Import non-license engine, process catalog and fixture-based tests from the sibling app.
- [x] Adapt overview, process detail, background items, browser review, internet, usage and menu-bar screens.
- [x] Connect the existing ClearDisk license and internal storage navigation; retain confirmation and execution-time checks.
- [x] Add optional monitoring settings, isolated usage history and stop/restart lifecycle handling.
- [x] Package the process catalog and Apple Events usage description/entitlement with the app.
- [x] Complete full regression (200 tests), universal build, package checks, main-window inspection and final diff/failure-path review; record results in `docs/2026-10-24-performance-integration.md`.
- [ ] Before production release, finish the menu-bar popover visual smoke test and permission-dependent actions on disposable data; these limits are recorded in the validation report.

## Review focus

Revoked entitlement between opening and confirming an action; overlapping cleanup and restart; self-termination; monitor cancellation and reentry; missing process resources; concurrent subprocess output and timeouts; history cleanup touching unrelated files; disabled menu-bar monitoring continuing after leaving the screen; unavailable browser/network data falsely presented as success.
