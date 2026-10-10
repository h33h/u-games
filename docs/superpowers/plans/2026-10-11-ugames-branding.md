# UGames branding implementation plan

**Goal:** Apply the approved violet/mint UGames identity across the portal on Android and iOS.
**Architecture:** Bundle local SVG artwork, the generated catalog background and scoped CSS into the shared document-start script. Keep game documents, resource URLs, user input and payment semantics intact.
**Spec:** User-approved resource audit in `shared/assets/brand-v2/resource-audit.json` and conversation.

- [x] Add regression coverage for portal-only styling, dynamic artwork, responsive logos, shadow roots and resource packaging.
- [x] Create SVG identity and category assets; inject a persistent portal stylesheet and data URLs into the shared adapter bundle.
- [x] Run the full shared test suite, lint and packaging; inspect desktop, mobile and game views in the live browser.

No separate worktree: this change continues the user's existing uncommitted branding work.

Review fixes: guard unchanged split-text writes to prevent observer loops; declare branding and asset inputs for Android incremental packaging.
