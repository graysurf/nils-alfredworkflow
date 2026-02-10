import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { extractSuggestFromHtml } from '../lib/extract_suggest.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const fixture = async (name) => {
  const fullPath = path.join(__dirname, 'fixtures', name);
  return readFile(fullPath, 'utf8');
};

test('extractSuggestFromHtml returns deduped ordered candidates (english)', async () => {
  const html = await fixture('suggest-english-open.html');
  const items = extractSuggestFromHtml({
    html,
    mode: 'english',
    maxResults: 10,
  });

  assert.equal(items.length, 3);
  assert.deepEqual(
    items.map((item) => item.entry),
    ['open', 'open up', 'open-minded'],
  );
  assert.ok(items[0].url.includes('/dictionary/english/open'));
});

test('extractSuggestFromHtml honors maxResults clamp', async () => {
  const html = await fixture('suggest-english-open.html');
  const items = extractSuggestFromHtml({
    html,
    mode: 'english',
    maxResults: 2,
  });

  assert.equal(items.length, 2);
});

test('extractSuggestFromHtml supports english-chinese-traditional mode', async () => {
  const html = await fixture('suggest-english-chinese-traditional-open.html');
  const items = extractSuggestFromHtml({
    html,
    mode: 'english-chinese-traditional',
    maxResults: 10,
  });

  assert.equal(items.length, 3);
  assert.ok(items[0].url.includes('/dictionary/english-chinese-traditional/open'));
});
