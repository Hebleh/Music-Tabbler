# Music Tabbler agent guidance

This file applies to the entire repository.

## Start here

- Read `docs/HANDOVER.md` first when resuming the current uncommitted work.
- Read `docs/CURRENT_STATUS.md` before planning or implementing work.
- Treat `docs/SPEC.md` as the product requirements.
- Treat `ARCHITECTURE.md` as the current technical direction.
- Preserve the manual screenshot/PDF workflow as a reliable fallback even while semantic recognition improves.

## Delegation hierarchy

Use a three-tier hierarchy to stretch Codex and NanoGPT limits without lowering verification quality:

1. **Codex is the primary agent.** Codex owns architecture, ambiguous product and music-domain behavior, security and legal-sensitive work, destructive changes, visual judgment, and final review and verification.
2. **GLM 5.2 is the secondary reasoning and coding reviewer.** Invoke the text-only NanoGPT model `zai-org/glm-5.2:thinking` through Pi for bounded higher-level code review, implementation alternatives, complex test design, and well-specified coding drafts. GLM has no vision capability: never ask it to inspect screenshots, rendered PDFs, or other images. NanoGPT quota is limited, so use concise prompts, avoid redundant passes, and reserve GLM for work that benefits from stronger reasoning.
3. **Qwen is the routine-work tier.** Prefer the local Pi/Qwen endpoint at `http://127.0.0.1:8080` for inventories, repetitive cross-checks, boilerplate with an exact specification, fixture cataloguing, mechanical refactors, test-matrix execution, and first-pass documentation cleanup. Query `/v1/models` before each delegation and use the model identifier it reports; never hard-code a transient model filename or claim a different served model is Qwen.

Pi's GitHub access is available again. It may be used for bounded, explicitly specified GitHub and release-packaging chores, but Codex retains commit/release scope decisions and final verification.

Before delegating, tell the user what is being offloaded. Prefer a read-only first pass and use a fresh, bounded, non-interactive prompt so the user's interactive Pi Dev session is untouched. Inspect every result before accepting it, and never report unavailable, timed-out, or unverified delegated work as complete.

Do not silently spend limited GLM quota on routine work when Qwen is unavailable. Codex should either handle the task or clearly report which fallback local model is actually being used. Do not start or reconfigure the user's model server without permission.

The local rig can generate slowly. Use a timeout of at least 20 minutes for substantive local work, provide periodic status updates, and do not treat quiet output or a timeout as success.

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
- Use `dev.bat` for normal Windows development (`dev.ps1` is the underlying PowerShell launcher). It launches `flutter run` and does not create a release package.
- During active development, verification normally means focused tests, the full relevant test suite, strict static analysis, a dev-mode smoke check, and representative chart/PDF visual checks.
- Do not create release builds, installers, archives, checksums, tags, or versioned packages during ordinary iteration. Run production builds and delegate mechanical packaging only for an explicit user-requested release or milestone checkpoint; Codex performs final artifact verification.
