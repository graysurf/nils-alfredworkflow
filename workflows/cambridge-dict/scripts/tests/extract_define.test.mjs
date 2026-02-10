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

test('extractDefineFromHtml keeps full definition text and skips def-info tokens', () => {
  const html = `
    <!doctype html>
    <html>
      <head>
        <title>take | Cambridge Dictionary</title>
        <link rel="canonical" href="https://dictionary.cambridge.org/dictionary/english/take" />
      </head>
      <body>
        <div class="entry-body">
          <h1 class="di-title"><span class="hw">take</span></h1>
          <div class="posgram"><span class="pos">verb</span></div>
          <div class="def-head"><span class="def-info">Add to word list</span></div>
          <div class="def-block">
            <div class="def ddef_d db">
              to remove <span class="gram">something</span>, especially without permission
            </div>
          </div>
        </div>
      </body>
    </html>
  `;

  const entry = extractDefineFromHtml({
    html,
    mode: 'english',
    entry: 'take',
  });

  assert.deepEqual(entry.definitions, ['to remove something, especially without permission']);
  assert.ok(!entry.definitions.includes('Add to word list'));
});
