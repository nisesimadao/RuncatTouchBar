## Context

<!-- Keep each pull request focused on one issue or feature. -->

- [ ] Bug fix
- [ ] Refactoring
- [ ] New feature
- [ ] Documentation
- [ ] Localization
- [ ] Other

## Summary

<!-- Explain what changes and which part of RuncatTouchBar is affected. -->

## Motivation

<!-- For behavior or feature changes, explain the user problem and why the change belongs in RuncatTouchBar rather than upstream RunCat Neo. -->

## Verification

<!-- Describe what you tested. For Touch Bar behavior, include physical-hardware testing when available. -->

- [ ] The project builds successfully.
- [ ] I tested the affected behavior.
- [ ] Touch Bar changes fail gracefully when the required private API is unavailable.
- [ ] Process-control changes target only the intended process and keep normal Quit and Force Quit clearly distinct.

## Checklist

- [ ] I have read [CONTRIBUTING.md](../blob/main/CONTRIBUTING.md).
- [ ] The diff is focused and does not contain unrelated refactors or formatting churn.
- [ ] Code follows [CODING_STYLE.md](../blob/main/CODING_STYLE.md).
- [ ] Layering follows [ARCHITECTURE.md](../blob/main/ARCHITECTURE.md).
- [ ] Any new private Touch Bar API dependency is guarded and documented.
- [ ] User-facing strings are placed in the localization resources where applicable.
- [ ] Documentation is updated when installation, security, supported systems, or user-visible behavior changes.
