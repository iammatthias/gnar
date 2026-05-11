---
name: init-project
description: >
  Bootstrap a new project directory so the agent can operate on it.
  Creates the directory if needed, initializes chainlink, drops a starter
  CLAUDE.md (if none exists), and registers the project in MEMORY.md so
  the orchestrator remembers it across sessions.

  Use this when the user asks to "start a new project", "set up a project
  at <path>", or refers to a path that doesn't have chainlink initialized
  yet.

inputs:
  project_path: Absolute path. Defaults to /srv/projects/<name> if just a
                name is given.
  description: Optional one-line description (used in CLAUDE.md and the
               MEMORY.md entry).

outputs:
  Confirmation summary listing which steps ran vs. were skipped.
---

# Procedure

Idempotent — re-running on an existing project is safe and skips any
step whose target already exists.

1. **Resolve `project_path`.** If the user said just `foo`, treat it as
   `/srv/projects/foo`. If absolute, use as-is.

2. **Create the directory.**
   ```
   mkdir -p <project_path>
   cd <project_path>
   ```

3. **Initialize chainlink.** If `.chainlink/issues.db` doesn't exist:
   ```
   chainlink init
   ```
   This is what lets `claude-with-chainlink` track issues + Claude sessions
   for the project later.

4. **Drop a starter `CLAUDE.md`.** If `CLAUDE.md` doesn't already exist
   in the project, write the following template (substituting `<name>`
   for the basename and `<description>` for the user-provided one, or
   `_(Add a one-line description here.)_` if none):

   ```markdown
   # <name>

   <description>

   ## Conventions

   - Language / framework:
   - Build system:
   - Test command:
   - Run-dev command:

   ## Layout

   ```
   (directory map — fill in once the project has structure)
   ```

   ## Notes for Claude

   - Anything Claude should *always* do (lint before commit, run tests
     after edits, etc.) goes here.
   - Anything Claude should *never* do (touch certain dirs, run network
     calls, etc.) goes here.
   ```

5. **Register in MEMORY.md.** Append to `/root/.hermes/MEMORY.md`:
   - Ensure a `## Projects` section exists; create it if missing.
   - Add the line `- <project_path>: <description>` *only if that path
     isn't already listed*.

6. **Return a summary** that names which of the 4 steps actually ran vs.
   were skipped, and the absolute project path.

# Notes

- Never `git init` here — let the user decide if the project should be a
  repo. They may want to `git clone` something existing into the path.
- Never modify a CLAUDE.md that already exists; the user may have
  hand-curated it.
- If MEMORY.md already lists the path, that's not an error — just say
  "already registered" in the summary.
