const BANGUMI_BASE_WEB = 'https://bgm.tv';
const BANGUMI_BASE_API = 'https://api.bgm.tv';

const TYPE_ALIASES = Object.freeze({
  all: 'all',
  book: 'book',
  anime: 'anime',
  music: 'music',
  game: 'game',
  real: 'real',
});

export const BANGUMI_TYPES = Object.freeze(Object.keys(TYPE_ALIASES));

function normalizeText(value) {
  return String(value ?? '').trim();
}

export function normalizeSubjectTypeToken(value) {
  const token = normalizeText(value).toLowerCase() || 'all';
  if (!TYPE_ALIASES[token]) {
    throw new Error(
      `invalid type token: ${value}. allowed values: ${BANGUMI_TYPES.join(', ')}`,
    );
  }
  return TYPE_ALIASES[token];
}

export function parseBangumiSearchInput(value) {
  const raw = normalizeText(value);
  if (!raw) {
    throw new Error('query must not be empty');
  }

  const parts = raw.split(/\s+/).filter(Boolean);
  const first = String(parts[0] ?? '').toLowerCase();

  if (TYPE_ALIASES[first]) {
    const query = parts.slice(1).join(' ').trim();
    if (!query) {
      throw new Error('query must not be empty');
    }
    return {
      type: TYPE_ALIASES[first],
      query,
      explicitType: true,
    };
  }

  return {
    type: 'all',
    query: raw,
    explicitType: false,
  };
}

export function buildSubjectSearchUrl({ query, type = 'all' }) {
  const parsed = parseBangumiSearchInput(`${type} ${query}`);
  const params = new URLSearchParams({
    cat: parsed.type,
    search_text: parsed.query,
  });
  return `${BANGUMI_BASE_WEB}/subject_search?${params.toString()}`;
}

export function buildV0SearchEndpoint() {
  return `${BANGUMI_BASE_API}/v0/search/subjects`;
}

export function buildSubjectUrl(subjectId) {
  const normalized = String(subjectId ?? '').trim();
  if (!/^\d+$/.test(normalized)) {
    throw new Error(`invalid subject id: ${subjectId}`);
  }
  return `${BANGUMI_BASE_WEB}/subject/${normalized}`;
}
