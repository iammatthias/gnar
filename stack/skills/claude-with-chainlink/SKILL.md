---
name: claude-with-chainlink
description: >
  Delegate a coding task to autonomous Claude Code in a project directory,
  with chainlink session tracking. Returns a summary plus the chainlink
  issue id so we can resume later. Use this for any task that touches
  project source code.

inputs:
  project_path: Absolute path to the project directory.
  task: What Claude should do.
  issue_id: Optional. If provided, resumes that chainlink issue and its
            prior Claude session. If omitted, creates a new issue.
  max_turns: Default 25.

outputs:
  Summary of work, chainlink issue id, claude session id (for resume).
---

# Procedure

1. cd into project_path. Verify `.chainlink/issues.db` exists (chainlink init
   must have been run there). If not, return an error — do NOT auto-init.

2. If issue_id was provided:
   - Run `chainlink show <issue_id>` to get current state.
   - Look in its comments for `claude-session: <uuid>` to resume.
   - Run `chainlink session start && chainlink session work <issue_id>`.

3. If issue_id was NOT provided:
   - Run `chainlink create "<one-line title from task>" -d "<task>" -p medium`
     and capture the new issue id.
   - Run `chainlink session start && chainlink session work <new_id>`.

4. Build the claude command:
   ```
   claude -p "<task>" \
     --output-format json \
     --permission-mode bypassPermissions \
     --max-turns <max_turns> \
     [--resume <session_id>]
   ```
   Run it via the `terminal` tool with workdir=project_path, timeout=1800.

5. Parse the JSON output for the new session_id.
   - If different from a prior one, store it: `chainlink comment <issue_id>
     "claude-session: <new_session_id>"`.

6. Run `chainlink session end --notes "<2-line summary of what changed>"`.

7. Return: { issue_id, session_id, summary, files_changed }.

# Notes

- bypassPermissions is the default. Pass `--permission-mode acceptEdits` only
  if the user explicitly says "be careful."
- Never auto-close the chainlink issue — let the user or a reviewer close it.
- If `claude -p` exits non-zero, comment the failure on the issue and return
  the error rather than silently retrying.
