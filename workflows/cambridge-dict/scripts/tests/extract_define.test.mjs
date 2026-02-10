import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { extractDefineFromHtml } from '../lib/extract_define.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const fixture = async (name) => {
  const fullPath = path.join(__dirname, 'fixtures', name);
  return readFile(fullPath, 'utf8');
};

test('extractDefineFromHtml parses english entry fields', async () => {
  const html = await fixture('define-english-open.html');
  const entry = extractDefineFromHtml({
    html,
    mode: 'english',
    entry: 'open',
  });

  assert.equal(entry.headword, 'open');
  assert.equal(entry.partOfSpeech, 'adjective');
  assert.deepEqual(entry.phonetics, ['/əʊ.pən/']);
  assert.deepEqual(entry.definitions, ['not closed or fastened', 'ready to allow people in']);
  assert.equal(entry.url, 'https://dictionary.cambridge.org/dictionary/english/open');
});

test('extractDefineFromHtml parses english-chinese-traditional entry fields', async () => {
  const html = await fixture('define-english-chinese-traditional-open.html');
  const entry = extractDefineFromHtml({
    html,
    mode: 'english-chinese-traditional',
    entry: 'open',
  });

  assert.equal(entry.headword, 'open');
  assert.equal(entry.partOfSpeech, 'adjective');
  assert.ok(entry.definitions.includes('開著的'));
  assert.ok(entry.definitions.includes('營業中的'));
  assert.equal(
    entry.url,
    'https://dictionary.cambridge.org/dictionary/english-chinese-traditional/open',
  );
});
