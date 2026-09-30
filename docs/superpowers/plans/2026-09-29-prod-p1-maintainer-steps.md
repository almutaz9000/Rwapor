# P1 release engineering: maintainer steps (to do later)

- **Board tasks**: `p1-release`, `p1-branch-main`, `p1-protect`, `p1-runiverse`,
  `p1-readme-runiverse` (parent `prod-p1`).
- **Status on 2026-09-29**: v1.0.5 is tagged at `aaa0739` (CI green). The steps below
  are GitHub admin or public actions that agents are not allowed to perform; the
  maintainer runs them. Do them **in this order** (each depends on the previous one).
- **Why** (agreed 2026-09-29): users get one fixed, citable version; installs no longer
  need a GitHub source build; nothing reaches the branch users install from unless CI
  passed (PR #220 merged 1.0.5 without the ETc fix, ISS-20260929-017).

Run the commands from the repo folder. In Claude Code, prefix each with `!`.

## 1. `p1-release`: publish the v1.0.5 GitHub release (5 min)

```
gh release create v1.0.5 --title "Rwapor 1.0.5" --notes "Fixes map scaling (10x too low in 1.0.4), wapor_map() return value, COG float truncation and ETc Kc alignment (ISS-20260929-017). See NEWS.md." --verify-tag
```

Done when: https://github.com/almutaz9000/Rwapor/releases shows 1.0.5.

## 2. `p1-branch-main`: make `main` the default branch (10 min)

The existing `main` is stale (last commit `e3aa832`, 2026-09-22). Its only unique
commits are docs changes that are already on the default branch in another form, so it
is archived, not merged.

```
gh api -X POST repos/almutaz9000/Rwapor/branches/main/rename -f new_name=archive/main-2026-09-22
gh api -X POST repos/almutaz9000/Rwapor/branches/version-1.0.4/rename -f new_name=main
```

Then update the local clone:

```
git fetch origin --prune
git branch -m version-1.0.4 main
git branch -u origin/main main
```

Notes:
- `remotes::install_github("almutaz9000/Rwapor")` keeps working (it uses the default branch).
- The workflows already trigger on `main` (`.github/workflows/*.yaml`); no change needed.
- Update any document that says `version-1.0.4` is the default branch
  (`agent-workflow/` files, `CLAUDE.md`/`AGENTS.md` adapters, the participant note if reused).

Done when: `gh api repos/almutaz9000/Rwapor --jq .default_branch` prints `main`.

## 3. `p1-protect`: require CI before anything reaches `main` (5 min)

```
gh api -X PUT repos/almutaz9000/Rwapor/branches/main/protection --input - <<'EOF'
{"required_status_checks":{"strict":false,"contexts":["windows-latest (release)","macos-latest (release)","ubuntu-latest (release)","install smoke (windows-latest)","lintr and styler"]},"enforce_admins":true,"required_pull_request_reviews":null,"restrictions":null}
EOF
```

- The check names are the job names in `.github/workflows/R-CMD-check.yaml`. R-devel
  and the manual live-API job are deliberately not required (they fail for reasons
  outside the package).
- Workflow after this: push work to a `version-*` branch (CI runs there), then
  fast-forward `main` once green, or open a PR. A commit without green checks is
  refused, also for admins.

Done when: `gh api repos/almutaz9000/Rwapor/branches/main/protection --jq '.required_status_checks.contexts'`
lists the five checks.

## 4. `p1-runiverse`: binary installs from R-universe (15 min + about 1 h build)

1. Create a public repository named exactly `almutaz9000.r-universe.dev` with one file,
   `packages.json`:

   ```json
   [
     {"package": "Rwapor", "url": "https://github.com/almutaz9000/Rwapor", "branch": "main"}
   ]
   ```

   (from the command line: `gh repo create almutaz9000/almutaz9000.r-universe.dev --public`,
   then add and push `packages.json`).
2. Install the R-universe GitHub app on the account:
   https://github.com/apps/r-universe/installations/new
3. Wait for the first build (about 1 hour), then check
   https://almutaz9000.r-universe.dev and test in a fresh R session:

   ```r
   install.packages("Rwapor", repos = c("https://almutaz9000.r-universe.dev", "https://cloud.r-project.org"))
   packageVersion("Rwapor")
   ```

Done when: the install above works on Windows without Rtools or a source build.

## 5. `p1-readme-runiverse`: document the new install route (agent task, after step 4)

Tell an agent "R-universe is live". It then adds the `install.packages(..., repos = ...)`
line as the first install option in `README.md` (keeping `install_github()` as the
development option), adds the same line to the training participant note template, and
extends the CI install smoke job to test the R-universe route.
