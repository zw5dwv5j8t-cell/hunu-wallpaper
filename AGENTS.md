## Shared Hunu Knowledge

### Before substantial work

Read `.agents/skills/hunu-knowledge/SKILL.md` and `.codex/hunu-knowledge.json`.
Run this sequence from the Wallpaper repository root before starting development,
even when a shared Hunu Knowledge checkout is already available.

```sh
runtime=$(python3 -B .agents/skills/hunu-knowledge/bootstrap.py) &&
  python3 -B "$runtime/tools/cloud_preflight.py" --project-path "$PWD" --runtime-path "$runtime" &&
  python3 -B "$runtime/integration/v1/client.py" read --source "$PWD" --project zw5dwv5j8t-cell/hunu-wallpaper
```

The launcher prints the isolated runtime path. Preflight verifies that its HEAD
matches the configured pin. Use the notes and `knowledge_base` commit returned by
the client, then continue the normal Wallpaper development workflow. Read central
`AGENTS.md` and search for additional relevant notes as directed by the skill.

If bootstrap, preflight, or retrieval fails, report the failing step and that
the standard integration was unavailable. If an existing checkout is available,
verify its Git origin and inspect its existing snapshot with read-only commands
such as `git rev-parse HEAD`, `git show`, and `git grep`. Report the inspected
commit as fallback evidence only. Leave the shared checkout untouched, including
its refs and working tree. Otherwise, proceed with the available project evidence.

### Before the final response

Follow the shared skill to evaluate durable discoveries and submit any eligible
handoff through the authorized intake route. If submission is blocked, report
the blocker and retain the private draft as directed by the skill.

### Pull requests and automatic merging

For routine changes, create a feature branch and pull request to `main`, run the
repository's test suite, and rely on GitHub Actions required checks. When the
repository has GitHub auto-merge enabled **and** the `Build and test (Arch Linux)`
check is required on `main`, enable GitHub auto-merge for the pull request.
Do not infer that local tests alone satisfy this gate, and never bypass branch
protections or push directly to `main`.

Do **not** enable auto-merge for changes involving authentication, secrets,
permissions, GitHub Actions/workflows, CI policies, install/uninstall or
destructive file operations, boot/display/session configuration, or other
changes that could disrupt an active desktop. Leave those PRs open for human
review. This file and the CI workflow itself are high-risk by this policy.

If branch protections or CI are missing, unknown, or failing, open the PR but
leave auto-merge off and report the specific blocker. Do not automatically
merge on a skipped or absent check. Keep the user's live machine unchanged
unless explicitly instructed and tested.
