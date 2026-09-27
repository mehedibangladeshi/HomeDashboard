import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateCommit } from './check-commit.mjs';

test('accepts multiple coherent task entries', () => {
  assert.deepEqual(validateCommit([
    '-> feat(auth): Route web sign-in links back to the browser while retaining native callbacks',
    '-> test(auth): Verify local email authentication and persisted household records in Chromium',
  ].join('\n')), []);
});
test('rejects short details, malformed format and AI attribution', () => {
  assert.ok(validateCommit('-> feat(auth): Fix login').length);
  assert.ok(validateCommit('feat(auth): Configure email authentication').length);
  assert.ok(validateCommit('Co-authored-by: Codex').length);
});
