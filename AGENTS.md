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
