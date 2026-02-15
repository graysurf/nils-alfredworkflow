import { normalizeSubjectTypeToken } from './bangumi_routes.mjs';

export const SCRAPER_SCHEMA_VERSION = '0.1.0';

function clampInteger(value, { fallback, min, max }) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, parsed));
}

function normalizeText(value) {
  return String(value ?? '').trim();
}

export function extractSearchFromHtml({ html, query, type = 'all', maxResults = 10 }) {
  const normalizedQuery = normalizeText(query);
  if (!normalizedQuery) {
    throw new Error('query must not be empty');
  }

  const normalizedType = normalizeSubjectTypeToken(type);
  const effectiveMaxResults = clampInteger(maxResults, { fallback: 10, min: 1, max: 20 });
  const source = String(html ?? '');

  return {
    schema_version: SCRAPER_SCHEMA_VERSION,
    stage: 'search',
    bridge_status: 'scaffold-not-implemented',
    type: normalizedType,
    query: normalizedQuery,
    items: [],
    meta: {
      parser: 'bangumi.extract_search.scaffold',
      html_bytes: Buffer.byteLength(source, 'utf8'),
      max_results: effectiveMaxResults,
    },
  };
}
