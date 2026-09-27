# Instructions for all agents

These rules apply to every directory in this repository and to every human or
automated agent preparing Git commits.

## Repository and identity

- GitHub repository: `git@github.com:mehedibangladeshi/HomeDashboard.git`
- GitHub account: `mehedibangladeshi`
- Git author and committer name: `Mehedi Hasan`
- Git author and committer email: `mehedipy@gmail.com`
- Configure identity locally in this repository, not globally.

## Required commit message format

Use one task entry per line in this exact form:

```text
-> <task_type>(<feature/module/directory/location>): <task details>
```

Each task details field must contain 60–100 characters, inclusive. The prefix,
task type, and parenthesized scope do not count toward that limit. Use a concrete
scope and plain language explaining the change and its outcome so the entries
can generate both technical and product-focused release notes.

Break work into small, meaningful tasks. Prefer a separate commit for each
coherent task; one commit may contain multiple task entries when the tasks
belong together. Every entry must independently follow the format and length
rule. Do not combine unrelated tasks just to reduce the number of commits.

Use task types such as `feat`, `fix`, `refactor`, `docs`, `test`, `build`, `ci`,
`perf`, or `chore`, according to the actual change.

Examples:

```text
-> feat(spending): Add receipt photo capture so household purchases retain proof of payment
-> fix(permissions): Prevent Managers from changing privileged roles or removing the last Owner
-> docs(git): Document repository identity and task commit rules for all future agents
```

## Attribution

Never add AI attribution to commits or repository contributor metadata. Never
add `Co-authored-by` trailers for Codex, Claude, another AI agent, or an AI
service. Never list AI as an author, committer, co-author, or contributor. Use
the configured human identity above for commits prepared on the user's behalf.

## Before committing

- Inspect the staged diff and keep unrelated changes out of the commit.
- Verify the message format and the 60–100 character task details limit for
  every entry.
- Run verification appropriate to the task.
- Never commit credentials, private keys, local environment files, build
  outputs, or dependency caches.
