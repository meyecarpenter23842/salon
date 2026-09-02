# POLISH-4 — Release Regression & Final Verification

## Baseline

- Repo: `meyecarpenter23842/salon`
- Base branch: `main`
- Base SHA: `5616a61838174dd53c487e9ff6c9e24b4e0a01c7`
- POLISH-1 → POLISH-3 are already merged into this baseline.
- This batch is verification/documentation first; production code changes are allowed only when regression evidence exposes a real defect.

## Scope

POLISH-4 closes the animation/interaction polish phase with a release-readiness gate:

- verify the approved main navigation remains exactly nine workspaces;
- render all nine workspaces through the real app shell at representative desktop sizes;
- rely on the existing regression suite for business/database behavior;
- preserve the motion, reduced-motion, focus/keyboard, loading/error and theme coverage introduced by POLISH-1 → POLISH-3;
- record what automated CI proves and what still requires a Windows desktop smoke test before an actual release.

Approved main workspaces:

1. Tổng quan
2. Lịch hẹn
3. Tính tiền
4. Khách hàng
5. Dịch vụ
6. Sản phẩm
7. Nhân viên
8. Báo cáo
9. Cài đặt

## Regression finding and fix

The first POLISH-4 push CI run (`#85`) passed `flutter analyze` and 66 tests, but the new full-shell matrix exposed a real responsive defect in **Khách hàng** at `1366 × 768`: the page remained in its fixed-height/`Expanded` layout after shell chrome consumed most of the available vertical space, leaving the customer list/detail workspace with almost no height and causing RenderFlex overflows.

The same management layout pattern and `< 620` vertical breakpoint existed in **Khách hàng, Dịch vụ, Nhân viên and Sản phẩm**. The fix is intentionally narrow and consistent: those four pages now enter their existing outer-scroll/short-viewport layout when the page viewport is below `760` pixels high. No cards, business flows, data providers, navigation modules or persistence behavior were changed.

The release regression test remains unchanged so the original failure condition continues to protect the fix.

## Automated release gate

The POLISH-4 regression test exercises every `DesktopSection` through `SalonManagerApp` with the fake runtime backend at:

- `1366 × 768`
- `1280 × 720`
- `1024 × 768`

For every size and workspace it verifies:

- the selected desktop section is preserved;
- the expected workspace label is rendered;
- no Flutter exception is raised while the workspace is mounted.

The full CI gate remains:

```text
flutter pub get
flutter analyze
flutter test
```

Existing tests continue to cover important release risks including appointment conflicts, checkout transactions, database bootstrap/cleanup, customer query semantics, backup flows, UI motion/reduced-motion, keyboard/focus interaction, four-theme rendering and shell navigation behavior.

## CI limitation / Windows smoke gate

GitHub Actions currently runs `flutter analyze` and `flutter test` on `ubuntu-latest`. That is strong source/regression evidence, but it does not prove the packaged Windows desktop executable behaves correctly with Windows-only integrations.

Before creating a real release, run a Windows smoke pass from the standard local checkout and verify at minimum:

- app launches and all nine main workspaces open;
- sidebar collapse/expand persists;
- appointment create/edit/status flow works;
- appointment → billing handoff works;
- checkout completes and recent invoice history updates;
- invoice PDF export/open works on Windows;
- reports CSV export writes successfully;
- backup/restore UI can access the expected local paths;
- keyboard focus is visible on interactive rows and Enter/Space activation works;
- reduced-motion behavior is acceptable with Windows animation settings disabled;
- all four approved themes remain readable at common desktop sizes.

## Explicitly unchanged

POLISH-4 does **not**:

- change database schema or run a migration;
- rewrite production data;
- change business logic, API, auth or permissions;
- add/remove main navigation modules;
- implement cloud sync or a phone client;
- deploy, publish, tag, or create a GitHub Release.

## Release readiness rule

The polish phase can be considered code-complete when the POLISH-4 branch/PR has a green `flutter analyze` and `flutter test` on its exact head SHA.

A production release should still wait for the Windows smoke gate above and an explicit release/deploy instruction.
