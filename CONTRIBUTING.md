# Contributing to RuncatTouchBar

Thank you for contributing to RuncatTouchBar.

RuncatTouchBar is an experimental macOS utility derived from [RunCat Neo](https://github.com/runcat-dev/RunCatNeo). This repository focuses on the Touch Bar / Control Strip integration and the supporting system-monitor UI.

## Before opening an issue

- Use **English** for issues, pull requests, code, identifiers, comments, and commit messages.
- Keep each issue focused on one problem or request.
- Search existing issues before opening a duplicate.
- This project targets **Touch Bar-equipped Macs**. Requests unrelated to the Touch Bar integration may belong in the upstream RunCat Neo repository instead.
- Runner requests and runner submissions belong in the upstream [Runner Gallery](https://runcat-dev.github.io/RunnerGallery/).

## Bug reports

Please include:

- macOS version;
- Mac model and architecture;
- whether the issue affects the Control Strip item, expanded Touch Bar monitor, shared RunCat state, or process controls;
- clear reproduction steps;
- relevant screenshots or logs when available.

Because this project uses private Touch Bar APIs, note whether the problem began after a macOS update.

## Feature requests

Explain the user problem first, then the proposed behavior. Please also describe why the feature belongs in the Touch Bar integration rather than upstream RunCat Neo.

Features that add maintenance cost, private-API surface area, or process-control behavior should include a clear benefit and scope.

## Pull requests

Keep pull requests small and focused. Avoid unrelated refactors, formatting-only changes, or cleanup in the same diff.

Before submitting a pull request:

1. Follow [ARCHITECTURE.md](ARCHITECTURE.md) and [CODING_STYLE.md](CODING_STYLE.md).
2. Preserve the Apache-2.0 headers in source files under `LocalPackage/Sources/`.
3. Keep user-facing strings in the localization resources.
4. Verify the project builds successfully.
5. When changing Touch Bar behavior, test on physical Touch Bar hardware when possible and describe what was tested.
6. When changing process actions, verify the target process is identified correctly and document any destructive behavior.

## Clone and build

Fork the repository, then clone your fork:

```bash
git clone https://github.com/your-username/RuncatTouchBar.git
cd RuncatTouchBar
```

Create a branch:

```bash
git switch -c descriptive-branch-name
```

For a quick physical-Touch-Bar test build:

```bash
bash scripts/build-test-app.sh
```

You can also build with Xcode or `xcodebuild`. The current source expects Xcode 26.5+ and Swift 6.2.

## Architecture rules

The codebase follows the RunCat Neo LUCA-style layering:

```text
UserInterface  →  Model  →  DataSource
```

The most important rules are:

- `DependencyClient` is a thin boundary around external effects, not a place for application logic.
- Views do not own control flow or business logic; state changes go through stores and their actions.
- `Model` does not reference Asset Catalog or String Catalog resources.
- Resource lookup and localization remain in `UserInterface`.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full contract.

## Private API changes

RuncatTouchBar dynamically resolves private Touch Bar APIs because Apple does not expose a public API for third-party Control Strip system-tray items.

If your change touches private APIs:

- keep symbol resolution guarded;
- fail gracefully when an API is unavailable;
- avoid assuming private selectors or symbols will remain stable across macOS versions;
- document newly introduced private API dependencies in the pull request.

## Process-control changes

The app can inspect and terminate user processes and therefore runs without App Sandbox.

Changes in this area must avoid broad or ambiguous process matching. Force-quit behavior is destructive and should remain clearly distinguishable from normal termination.

See [docs/SECURITY.md](docs/SECURITY.md) for the current security model.

## Upstream changes

If a change improves RunCat Neo generally and is not specific to RuncatTouchBar, consider contributing it upstream first. When this repository intentionally diverges from upstream, keep the reason clear in the pull request so future rebases remain understandable.

## License

By contributing, you agree that your contribution will be distributed under the repository's Apache License 2.0 terms.
