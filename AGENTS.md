# Music Tabbler agent guidance

This file applies to the entire repository.

## Start here

- Read `docs/CURRENT_STATUS.md` before planning or implementing work.
- Treat `docs/SPEC.md` as the product requirements.
- Treat `ARCHITECTURE.md` as the current technical direction.
- Preserve the manual screenshot/PDF workflow as a reliable fallback even while semantic recognition improves.

## Local-model delegation

Use the user's local Pi/Qwen model for large, routine, well-bounded work when it is available. Good candidates include inventories, repetitive cross-checks, boilerplate with an exact specification, fixture cataloguing, test-matrix execution, and first-pass documentation cleanup.

Before delegating, tell the user what is being offloaded. Prefer a read-only first pass. Keep architecture decisions, music-domain ambiguity, security or legal-sensitive work, destructive edits, and final review/verification with the primary agent. Inspect every result before accepting it.

Prefer direct non-interactive delegation through the configured Qwen endpoint at `http://127.0.0.1:8080`. Use a fresh bounded prompt and do not modify the user's interactive Pi Dev session. Do not start or reconfigure the model server without permission.

The local rig generates slowly. Use a timeout of at least 20 minutes for substantive work, provide periodic status updates, and do not treat quiet output or a timeout as success.

## Product and safety rules

- The app is local-first: no required cloud account, cloud processing, telemetry, or CDN assets.
- Recognition is an editable proposal. Never silently treat OCR/OMR output as verified music.
- Keep pitch transposition separate from same-pitch re-tabbing for another tuning or string count.
- Never lose the current library during state import. Validate in staging and retain a last-known-good backup before replacement.
- Source provenance stays in the app and must never leak into chart or PDF rendering.
- Direct-URL and search adapters must not bypass authentication, paid features, CAPTCHAs, rate limits, or technical restrictions. A VPN does not change this rule.
- Do not claim a source adapter is legally distributable until the relevant terms, content rights, and dependency licenses have been reviewed.
- Do not claim OCR/OMR accuracy without reporting the fixture set, metric, threshold, and manual corrections required.

## Engineering rules

- Keep the semantic domain model independent of UI, persistence, source acquisition, and OCR/OMR engines.
- Windows is implemented first, but shared behavior must remain compatible with the planned full Android application.
- Use deterministic rendering for screen and A4 PDF; test both tab-only and tab-plus-notation layouts.
- Store stylus annotations as nondestructive vector overlays.
- Add migration tests before changing persisted schemas or bundle formats.
- Verification for relevant changes must include unit tests, strict static analysis, a production build for the affected platform, and visual checks of representative charts/PDFs.
