import assert from 'node:assert/strict';
import test from 'node:test';

import {
  CAMBRIDGE_BASE_URL,
  CAMBRIDGE_MODES,
  buildDefineUrl,
  buildSuggestUrl,
  normalizeMode,
} from '../lib/cambridge_routes.mjs';

test('normalizeMode accepts supported modes', () => {
  assert.equal(normalizeMode('english'), 'english');
  assert.equal(normalizeMode('english-chinese-traditional'), 'english-chinese-traditional');
  assert.equal(normalizeMode('  English  '), 'english');
});

test('normalizeMode rejects unsupported mode', () => {
  assert.throws(() => normalizeMode('english-chinese-simplified'), /invalid mode/i);
});

test('buildSuggestUrl encodes query and mode dataset', () => {
  const url = buildSuggestUrl({ query: 'open up', mode: 'english' });
  assert.equal(
    url,
    `${CAMBRIDGE_BASE_URL}/search/direct/?datasetsearch=english&q=open%20up`,
  );
});

test('buildDefineUrl builds dictionary path per mode', () => {
  const url = buildDefineUrl({ entry: 'open up', mode: 'english-chinese-traditional' });
  assert.equal(
    url,
    `${CAMBRIDGE_BASE_URL}/dictionary/english-chinese-traditional/open-up`,
  );
});

test('mode list is stable', () => {
  assert.deepEqual(CAMBRIDGE_MODES, ['english', 'english-chinese-traditional']);
});
