import assert from 'node:assert/strict';
import test from 'node:test';

import { selectorsForMode, selectorsForStage } from '../lib/cambridge_selectors.mjs';

test('selector registry exposes suggest and define chains', () => {
  const selectors = selectorsForMode('english');
  assert.ok(selectors.suggest.candidateHeadwords.length > 0);
  assert.ok(selectors.suggest.candidateLinks.length > 0);
  assert.ok(selectors.define.headword.length > 0);
  assert.ok(selectors.define.definitions.length > 0);
});

test('traditional chinese mode keeps translation selectors first', () => {
  const selectors = selectorsForMode('english-chinese-traditional');
  assert.equal(selectors.define.definitions[0], '.entry-body .trans');
});

test('selectorsForStage validates stage', () => {
  assert.throws(
    () => selectorsForStage({ mode: 'english', stage: 'unknown' }),
    /unknown stage/i,
  );
});
