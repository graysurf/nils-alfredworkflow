const CAMBRIDGE_BASE_URL = 'https://dictionary.cambridge.org';
const MODE_DATASET = {
  english: 'english',
  'english-chinese-traditional': 'english-chinese-traditional',
};

export const CAMBRIDGE_MODES = Object.freeze(Object.keys(MODE_DATASET));

function toLowerTrimmed(value) {
  return String(value ?? '').trim().toLowerCase();
}

export function normalizeMode(mode) {
  const normalized = toLowerTrimmed(mode || 'english');
  if (!MODE_DATASET[normalized]) {
    throw new Error(
      `invalid mode: ${mode}. allowed values: ${CAMBRIDGE_MODES.join(', ')}`,
    );
  }
  return normalized;
}

export function sanitizeEntry(value) {
  const normalized = String(value ?? '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
  if (!normalized) {
    throw new Error('entry must not be empty');
  }
  return normalized;
}

export function entryToPathSegment(entry) {
  return sanitizeEntry(entry)
    .split(' ')
    .filter(Boolean)
    .map((segment) => encodeURIComponent(segment))
    .join('-');
}

export function buildSuggestUrl({ query, mode }) {
  const normalizedMode = normalizeMode(mode);
  const q = sanitizeEntry(query);
  const dataset = MODE_DATASET[normalizedMode];
  return `${CAMBRIDGE_BASE_URL}/search/direct/?datasetsearch=${dataset}&q=${encodeURIComponent(q)}`;
}

export function buildDefineUrl({ entry, mode }) {
  const normalizedMode = normalizeMode(mode);
  const slug = entryToPathSegment(entry);
  return `${CAMBRIDGE_BASE_URL}/dictionary/${normalizedMode}/${slug}`;
}

export function buildRouteSet({ query, entry, mode }) {
  const normalizedMode = normalizeMode(mode);
  return {
    mode: normalizedMode,
    suggestUrl: buildSuggestUrl({ query, mode: normalizedMode }),
    defineUrl: buildDefineUrl({ entry, mode: normalizedMode }),
  };
}

export function isSupportedMode(mode) {
  const normalized = toLowerTrimmed(mode);
  return Boolean(MODE_DATASET[normalized]);
}

export { CAMBRIDGE_BASE_URL };
