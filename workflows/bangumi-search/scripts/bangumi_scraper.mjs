#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import { buildSubjectSearchUrl, parseBangumiSearchInput } from './lib/bangumi_routes.mjs';
import { asStructuredError, ERROR_CODES } from './lib/error_classify.mjs';
import { SCRAPER_SCHEMA_VERSION, extractSearchFromHtml } from './lib/extract_search.mjs';

const HELP_TEXT = `Usage:
  bangumi_scraper.mjs search --input "[type] query" [--max-results <n>] [--fixture-html <path>]
  bangumi_scraper.mjs --help

Type tokens:
  all | book | anime | music | game | real

Status:
  Scaffold only. This bridge is disabled by default in workflow runtime.
`;

function clampInteger(value, { fallback, min, max }) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, parsed));
}

function parseCli(argv) {
  if (argv.length === 0 || argv[0] === '--help' || argv[0] === '-h') {
    return { help: true };
  }

  const command = argv[0];
  if (command !== 'search') {
    throw new Error(`unknown argument: ${command}`);
  }

  const args = {
    help: false,
    command,
    input: '',
    maxResults: process.env.BANGUMI_MAX_RESULTS || '10',
    fixtureHtml: '',
  };

  for (let i = 1; i < argv.length; i += 1) {
    const token = argv[i];
    const next = argv[i + 1];

    const consume = (name) => {
      if (!next || next.startsWith('--')) {
        throw new Error(`${name} requires a value`);
      }
      i += 1;
      return next;
    };

    if (token === '--input') {
      args.input = consume('--input');
    } else if (token === '--max-results') {
      args.maxResults = consume('--max-results');
    } else if (token === '--fixture-html') {
      args.fixtureHtml = consume('--fixture-html');
    } else if (token === '--help' || token === '-h') {
      args.help = true;
      return args;
    } else {
      throw new Error(`unknown argument: ${token}`);
    }
  }

  if (!String(args.input).trim()) {
    throw new Error('query must not be empty');
  }

  args.maxResults = clampInteger(args.maxResults, { fallback: 10, min: 1, max: 20 });
  return args;
}

function writeJson(payload) {
  process.stdout.write(`${JSON.stringify(payload)}\n`);
}

async function main() {
  let args;
  try {
    args = parseCli(process.argv.slice(2));
  } catch (error) {
    writeJson(asStructuredError({ stage: 'bootstrap', error }));
    process.exit(2);
  }

  if (args.help) {
    process.stdout.write(HELP_TEXT);
    return;
  }

  let parsed;
  try {
    parsed = parseBangumiSearchInput(args.input);
  } catch (error) {
    writeJson(asStructuredError({ stage: 'bootstrap', error }));
    process.exit(2);
  }

  const enabled = String(process.env.BANGUMI_SCRAPER_ENABLE ?? '')
    .trim()
    .toLowerCase() === 'true';

  if (!enabled) {
    writeJson({
      ok: false,
      schema_version: SCRAPER_SCHEMA_VERSION,
      stage: 'bootstrap',
      feature: 'playwright-bridge',
      enabled: false,
      request: {
        type: parsed.type,
        query: parsed.query,
        max_results: args.maxResults,
        url: buildSubjectSearchUrl({ query: parsed.query, type: parsed.type }),
      },
      error: {
        code: ERROR_CODES.NOT_IMPLEMENTED,
        message: 'bangumi scraper bridge is disabled by default',
        hint: 'keep API-first runtime path; enable BANGUMI_SCRAPER_ENABLE=true only after rollout gates',
        retriable: false,
      },
    });
    process.exit(1);
  }

  let html = '';
  if (args.fixtureHtml) {
    html = await readFile(args.fixtureHtml, 'utf8');
  }

  const extracted = extractSearchFromHtml({
    html,
    query: parsed.query,
    type: parsed.type,
    maxResults: args.maxResults,
  });

  writeJson({
    ok: false,
    schema_version: SCRAPER_SCHEMA_VERSION,
    stage: 'search',
    feature: 'playwright-bridge',
    enabled: true,
    request: {
      type: parsed.type,
      query: parsed.query,
      max_results: args.maxResults,
      url: buildSubjectSearchUrl({ query: parsed.query, type: parsed.type }),
    },
    extracted,
    error: {
      code: ERROR_CODES.NOT_IMPLEMENTED,
      message: 'bangumi scraper extraction bridge is scaffolded but not production-enabled',
      hint: 'complete rollout gates before switching runtime from API-first',
      retriable: false,
    },
  });
  process.exit(1);
}

await main();
