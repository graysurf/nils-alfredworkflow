import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const scraperPath = path.resolve(__dirname, '..', 'bangumi_scraper.mjs');

function runScraper(args, env = {}) {
  const result = spawnSync(process.execPath, [scraperPath, ...args], {
    encoding: 'utf8',
    env: {
      ...process.env,
      ...env,
    },
  });

  const stdout = result.stdout.trim();
  let payload = null;
  if (stdout.startsWith('{') || stdout.startsWith('[')) {
    payload = JSON.parse(stdout);
  }

  return {
    ...result,
    stdout,
    payload,
  };
}

test('help output is available', () => {
  const run = runScraper(['--help']);
  assert.equal(run.status, 0);
  assert.match(run.stdout, /Usage:/);
  assert.match(run.stdout, /disabled by default/i);
});

test('default runtime path is disabled and returns structured envelope', () => {
  const run = runScraper(['search', '--input', 'anime naruto']);
  assert.equal(run.status, 1);
  assert.equal(run.payload.ok, false);
  assert.equal(run.payload.enabled, false);
  assert.equal(run.payload.error.code, 'not_implemented');
  assert.equal(run.payload.request.type, 'anime');
  assert.equal(run.payload.request.query, 'naruto');
});

test('invalid args return invalid_args envelope', () => {
  const run = runScraper(['search', '--unknown', 'value']);
  assert.equal(run.status, 2);
  assert.equal(run.payload.ok, false);
  assert.equal(run.payload.error.code, 'invalid_args');
});

test('feature flag path still returns scaffolded non-production envelope', () => {
  const run = runScraper(['search', '--input', 'book 三体'], {
    BANGUMI_SCRAPER_ENABLE: 'true',
  });
  assert.equal(run.status, 1);
  assert.equal(run.payload.ok, false);
  assert.equal(run.payload.enabled, true);
  assert.equal(run.payload.error.code, 'not_implemented');
  assert.equal(run.payload.request.type, 'book');
});
