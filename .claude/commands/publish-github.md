---
description: Scan for secrets, push to GitHub, publish the site via Pages, then write the README and repo About.
argument-hint: [repo URL or owner/name — omit to use the existing origin remote]
allowed-tools: Bash(git:*), Bash(curl:*), Bash(grep:*), Bash(rg:*), Bash(ls:*), Bash(cat:*), Read, Write, Edit, Grep, Glob
---

Publish this project to GitHub end to end: secret scan, push, Pages deployment, README, and the
repository About blurb.

Target repository: **$1** — if empty, use the current `origin` remote. Accept either a full URL
(`https://github.com/owner/name`) or `owner/name`. If neither is given and there is no `origin`, stop and
ask which repository to publish to; never guess or create a repository without being asked.

Current state for reference:

- Remote: !`git remote -v 2>/dev/null | head -2 || echo "(no remote)"`
- Branch: !`git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(no commits)"`
- Working tree: !`git status --short 2>/dev/null | head -20 || echo "(not a git repo)"`

Work through the steps in order. Each one gates the next — do not skip ahead, and report honestly if a
step cannot be completed rather than proceeding as though it succeeded.

## 1. Secret scan — before anything is pushed

This runs first by design. A push publishes every commit, so scanning after upload would be too late:
the exposure has already happened, and rewriting history does not reliably undo it (forks, caches, and
anyone who already fetched still have the object).

Scan **both** the working tree and the commit history that would be pushed — `git log -p` content ships
with the push even when the file is long gone from `HEAD`.

Look for, at minimum:

- Private keys and certificates: `BEGIN (RSA|OPENSSH|DSA|EC|PGP) PRIVATE KEY`, `.pem`, `.key`, `.p12`, `.pfx`
- Cloud and provider credentials: `AKIA[0-9A-Z]{16}` (AWS), `ASIA[0-9A-Z]{16}`, `AIza[0-9A-Za-z_-]{35}`
  (Google), `ya29.`, Azure connection strings (`AccountKey=`, `SharedAccessSignature`)
- Tokens: `gh[pousr]_[A-Za-z0-9]{36,}`, `github_pat_`, `xox[baprs]-` (Slack), `sk-`/`sk-ant-`, `Bearer `
  followed by a long opaque string, JWTs (`eyJ[A-Za-z0-9_-]{10,}\.`)
- Generic assignments: `(password|passwd|pwd|secret|token|api[_-]?key|client[_-]?secret|credential)`
  followed by `=` or `:` and a non-placeholder literal
- Connection strings with inline credentials: `://user:password@host`
- Environment and credential files: `.env`, `.env.*`, `credentials`, `id_rsa`, `*.keystore`,
  `serviceAccount*.json`, `*.sqlite`/`*.db` holding real data
- Internal-only identifiers: private hostnames, internal IPs, VPN endpoints, real customer or employee
  names, real email addresses, ticket links behind a corporate SSO

Judge each hit rather than pattern-matching blindly. A placeholder (`YOUR_EMAIL@example.com`,
`<your-token-here>`, `xxx`, an obvious dummy) is fine and should stay a placeholder. A real-looking
credential is a stop.

**If anything real is found: stop. Do not push.** Report the file and line — describe the location, never
paste the secret value into chat or a commit. Then propose the fix (remove it, replace with a placeholder,
move it to an untracked config file plus a `.gitignore` entry, and rotate the credential if it was ever
committed). Resume only when the user says to.

Also confirm `.gitignore` covers the obvious sources before continuing, and that no ignored-but-tracked
file is about to ship (`git ls-files -ci --exclude-standard`).

## 2. Push the code

- Verify you are on the intended branch. Respect any branch instruction in `CLAUDE.md` or the session's
  own branch requirements — do not push to a different branch without explicit permission.
- If the target repo from `$1` differs from the current `origin`, confirm with the user before repointing
  the remote.
- Stage and commit anything outstanding with a descriptive message. Never commit a file that step 1
  flagged.
- Push with `git push -u origin <branch>`. On network failure retry up to 4 times, backing off 2s, 4s, 8s,
  16s. Do not open a pull request unless the user asks for one.

## 3. GitHub Pages via Actions

Check `.github/workflows/` for an existing Pages workflow and edit it rather than adding a second one.
If none exists, create `.github/workflows/deploy-pages.yml`: trigger on push to the default branch plus
`workflow_dispatch`; grant `contents: read`, `pages: write`, `id-token: write`; stage the site into
`_site/` and publish with `actions/upload-pages-artifact` and `actions/deploy-pages`. Keep a `concurrency`
group so a running deployment is not cancelled mid-publish.

Then trigger a run and read the logs — a workflow that was written but never verified is not done.

Known blockers, worth checking before blaming the workflow:

- **Pages is unavailable on private repos on the Free plan.** Check `visibility` and `has_pages` via
  `GET /repos/{owner}/{repo}`. If it is private on Free, Pages cannot be enabled at all: the site must be
  made public or the account upgraded. Surface this as a choice for the user, not a unilateral change —
  making a repo public is irreversible in effect and theirs to decide.
- **`GITHUB_TOKEN` cannot create a Pages site.** `actions/configure-pages` with `enablement: true` fails
  with `Resource not accessible by integration`; creating the site needs admin rights the Actions token
  never has. Pages must be switched on once by hand at Settings → Pages → Source: GitHub Actions.
- **`Get Pages site failed: Not Found`** in the log means Pages is still not enabled — that is the
  diagnostic, not a workflow bug.
- Some sandboxes block the Pages REST API path and `*.github.io` entirely. If so, say plainly that you
  cannot enable or fetch the live page yourself, and verify via the workflow run and the `deploy-pages`
  step's reported URL instead of claiming the page loads.
- Commit a root `.nojekyll` as well as `_site/.nojekyll` so publishing straight from a branch works as a
  fallback that needs no workflow run and no OIDC token.
- Give the page an inline `data:` URI favicon. Browsers request `/favicon.ico` automatically on every
  load, and without one that is a guaranteed 404 on the live site.

## 4. README

Create or update `README.md`. Edit around what is already there — preserve any hand-written sections
rather than overwriting the file wholesale. Cover what the project is, how to run it locally, how it is
deployed, and any constraints a contributor would otherwise break. Include the live Pages link once it
exists. Keep it to what is true of this repository — do not invent badges, licences, roadmaps, or support
channels that were never agreed.

## 5. Repository About

Set the repo description and homepage so the Pages link appears in the About panel:

```
curl -sS -X PATCH \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" \
  https://api.github.com/repos/{owner}/{repo} \
  --data-raw '{"description":"…","homepage":"https://{owner}.github.io/{repo}/"}'
```

Keep the description to one line. If the call is refused (blocked API path, insufficient scope), say so and
give the user the exact text to paste into the About panel themselves rather than reporting success.

## Finally

Report what actually happened per step: what was scanned and found, what was pushed, the workflow run
conclusion, and the live URL. If a step was blocked, name the blocker and what the user needs to do. Do not
describe the page as live unless a successful deployment says so.
