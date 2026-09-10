# Development Workflow

The shared release baseline is `main`, tracking `origin/main`.

Use short-lived `codex/<task>` branches for substantial changes. Merge verified
work back into `main` and delete the merged task branch. Do not leave completed
work uncommitted across release cycles. A Git commit and a TestFlight upload
are separate checkpoints; record the source commit for every future archive.

## 2026-09-10 Consolidation

The current iOS source, tests, release tooling, and documentation were committed
and merged with the remote support, privacy, and review-demo changes.
Historical migration and original main tips remain available under
`archive/pre-consolidation-*-20260910` tags. Obsolete temporary worktree metadata
was pruned after verifying its directories no longer exist.

The fnOS package initiative is paused at the owner's request. Existing source
and reports are retained for reference; no further packaging, installation, or
release is planned. Generated FPK and iOS distribution files are not committed.

Current source declares version 1.0 build 19. Prior validation and upload
records are historical evidence, not a new verification of the current build.
