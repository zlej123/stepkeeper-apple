# stepkipper

The video gets deleted. The steps stay yours.

A SwiftUI app (iOS/iPadOS/macOS) that turns a YouTube how-to video into a follow-along document.
Where the narration only says something vague — *"cut it bite-sized"*, *"sear until golden brown"* —
the document carries the actual frame that shows it (you pick which one), or a timestamp link.
Finished documents go out through the share sheet, into a folder, or straight into a Notion page
(with your own integration token).

stepkipper is the Apple client of the [stepkeeper](https://github.com/zlej123/stepkeeper) ecosystem: analysis calls
Gemini directly from the app (BYOK) by default, [stepkeeper-server](https://github.com/zlej123/stepkeeper-server)
is optional (development, prompt iteration, hosting the report collector), frames are captured in the
app's own WKWebView (nothing is downloaded from YouTube), and the document is assembled locally
(skill-core templates + a Swift port of the core renderer, pinned to it by golden tests).

This is a pre-release app, so its product name and internal Apple identifiers consistently use
`stepkipper`: the `com.stepkipper.*` bundle IDs, App Group, Keychain services, storage path,
Xcode targets and scheme, and Swift module all share the same spelling.

## Languages

Two independent axes, deliberately:

- **App UI** follows the **system language** (`Resources/Localizable.xcstrings`, English source + Korean).
- **Document body** follows the **language the document was made in** (`DocumentStrings`), matching the
  core's `template.<lang>.md`. A Korean document opened on an English device stays Korean.

Languages without a translation fall back to English, never to Korean.

## Development

Requires: Xcode 26+, XcodeGen (`brew install xcodegen`), Python 3.10+ (for the scripts)

    xcodegen generate                # project.yml → xcodeproj
    open stepkipper-apple.xcodeproj

    # Tests (CLI; set DEVELOPER_DIR if xcode-select points at the Command Line Tools)
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    xcodebuild -project stepkipper-apple.xcodeproj -scheme Stepkipper \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
    xcodebuild -project stepkipper-apple.xcodeproj -scheme Stepkipper \
      -destination 'platform=macOS' test

    # E2E (stub server — no Gemini key needed)
    ./scripts/e2e-m1.sh              # link mode
    ./scripts/e2e-m2.sh              # real YouTube capture

Tests never touch the real Keychain: production items are inert under test, and the model takes an
injected `SecretStoring` (see `Tests/InMemorySecretStore.swift`). This matters on macOS — the app is
ad-hoc signed, the signature changes every build, and reading an item a previous build created pops a
Keychain approval dialog that a headless runner can never answer.

## Scripts

- `scripts/stub-server.py` — `/v1/analyze` stub that replies from a fixture
- `scripts/sync-assets.sh` — re-copy skill-core assets (templates, prompts, schemas, rules) from
  `../stepkeeper`, then apply the Apple product's `stepkipper` branding; the direct-Gemini path uses
  the prompt and schema, so regenerate goldens after
- `scripts/make-golden.py` — regenerate markdown goldens with the core's `render.py`, then apply the
  same `stepkipper` branding adapter
- `scripts/make-notion-golden.py` — regenerate Notion block goldens with the core's `build_notion_blocks`
- `scripts/spike-verify.sh` — capture stability check on the simulator (the M0 spike). It launches the
  app with `STEPKIPPER_SPIKE=1`, which roots a DEBUG-only `SpikeCaptureView` harness. Re-run it when
  Xcode, iOS, or YouTube's player changes — it is the only way to re-measure capture timing and
  frame-to-frame variance, so the harness stays in the tree on purpose

## Docs

- Design specs: `docs/superpowers/specs/` (v1 · Notion export · onboarding · one-tap reports · serverless)
- Capture spike write-up: `docs/spike-capture.md`
- Manual test checklist: `docs/TESTING.md`
- Deploying the report collector: `../stepkeeper-server/docs/deploy.md`
