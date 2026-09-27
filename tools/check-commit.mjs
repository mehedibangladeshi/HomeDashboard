import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

export function validateCommit(message) {
  const errors = [];
  const lines = message.trim().split(/\r?\n/).filter(line => line.trim());
  if (!lines.length) errors.push('Commit must contain a task entry.');
  for (const line of lines) {
    const match = /^-> (feat|fix|refactor|docs|test|build|ci|perf|chore)\(([^()]+)\): (.+)$/.exec(line);
    if (!match) { errors.push('Every nonempty line must follow the task commit format.'); continue; }
    const length = [...match[3]].length;
    if (length < 60 || length > 100) errors.push(`Task details have ${length} characters; expected 60–100.`);
  }
  if (/co-authored-by|\b(codex|claude|openai|anthropic)\b/i.test(message)) {
    errors.push('AI attribution is not permitted.');
  }
  return errors;
}

if (process.argv[2]) {
  const message = process.argv[2] === '--last'
    ? spawnSync('git', ['log', '-1', '--format=%B'], { encoding: 'utf8' }).stdout
    : readFileSync(process.argv[2], 'utf8');
  const errors = validateCommit(message);
  errors.forEach(error => console.error(error));
  process.exitCode = errors.length ? 1 : 0;
}
