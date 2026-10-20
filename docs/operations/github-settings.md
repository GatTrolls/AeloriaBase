# GitHub repository settings

Repository settings cannot be stored in git, so they are listed here. The two rulesets are
saved as JSON in `.github/rulesets/` and can be imported.

## Rulesets (Settings → Rules → Rulesets → New ruleset → Import a ruleset)

| File | Protects | Rules |
| --- | --- | --- |
| `.github/rulesets/main.json` | The default branch (`main`) | No deletion, no force-push, changes only by pull request, conversations resolved, squash merge only, CI `check` must pass |
| `.github/rulesets/release-tags.json` | Tags `v*` | Release tags can't be moved or deleted |

Repository admins can bypass both, so an emergency fix is never blocked. No approving review
is required, because GitHub does not let an author approve their own pull request. Raise
`required_approving_review_count` to 1 once a second developer joins.

## General

- Pull Requests: allow **squash merging** only; turn on **Automatically delete head branches**.
- Features: turn the GitHub Wiki off (docs live in `docs/`); Issues and Projects on;
  Discussions optional.

## Security (Settings → Code security), all free on public repos

- Dependabot alerts and security updates: on.
- Secret scanning and push protection: on.
- Private vulnerability reporting: on (used by `SECURITY.md`).

## Pages (Settings → Pages)

- Source: **GitHub Actions**. Then run the "Deploy website" workflow from the Actions tab.
