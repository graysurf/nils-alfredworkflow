import { CAMBRIDGE_BASE_URL, buildDefineUrl, normalizeMode, sanitizeEntry } from './cambridge_routes.mjs';
import { selectorsForStage } from './cambridge_selectors.mjs';

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function decodeHtmlEntities(value) {
  return value
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) =>
      String.fromCodePoint(Number.parseInt(hex, 16)),
    )
    .replace(/&#([0-9]+);/g, (_, code) => String.fromCodePoint(Number.parseInt(code, 10)));
}

function stripTags(value) {
  return decodeHtmlEntities(value.replace(/<[^>]+>/g, ' '));
}

function normalizeText(value) {
  return stripTags(String(value ?? ''))
    .replace(/\s+/g, ' ')
    .trim();
}

function primaryClassFromSelector(selector) {
  const classes = [...String(selector).matchAll(/\.([a-zA-Z][\w-]*)/g)].map((match) => match[1]);
  if (classes.length === 0) {
    return '';
  }
  return classes[classes.length - 1];
}

function collectClassTexts(html, className) {
  const pattern = new RegExp(
    `<[^>]*class=(['"])` +
      `[^'"]*\\b${escapeRegExp(className)}\\b[^'"]*` +
      `\\1[^>]*>([\\s\\S]*?)<\\/[^>]+>`,
    'gi',
  );

  const texts = [];
  for (const match of html.matchAll(pattern)) {
    const normalized = normalizeText(match[2]);
    if (normalized) {
      texts.push(normalized);
    }
  }
  return texts;
}

function extractEntryFromHref(href, mode) {
  const normalizedMode = normalizeMode(mode);
  const pattern = new RegExp(`/dictionary/${escapeRegExp(normalizedMode)}/([^/?#]+)`, 'i');
  const match = String(href).match(pattern);
  if (!match || !match[1]) {
    return null;
  }

  const decoded = decodeURIComponent(match[1]).replace(/-/g, ' ').trim();
  return decoded || null;
}

function absolutizeUrl(href) {
  const raw = String(href ?? '').trim();
  if (!raw) {
    return '';
  }
  if (/^https?:\/\//i.test(raw)) {
    return raw;
  }
  if (raw.startsWith('/')) {
    return `${CAMBRIDGE_BASE_URL}${raw}`;
  }
  return `${CAMBRIDGE_BASE_URL}/${raw}`;
}

function collectLinkCandidates(html, mode) {
  const pattern = /<a\b[^>]*href=(['"])([^'"]+)\1[^>]*>([\s\S]*?)<\/a>/gi;
  const candidates = [];

  for (const match of html.matchAll(pattern)) {
    const href = match[2];
    if (!href.includes('/dictionary/')) {
      continue;
    }

    const entry = extractEntryFromHref(href, mode);
    if (!entry) {
      continue;
    }

    const label = normalizeText(match[3]) || entry;
    candidates.push({
      entry,
      label,
      url: absolutizeUrl(href),
    });
  }

  return candidates;
}

function clampMaxResults(maxResults) {
  const parsed = Number.parseInt(String(maxResults ?? '8'), 10);
  if (!Number.isFinite(parsed)) {
    return 8;
  }
  return Math.min(20, Math.max(1, parsed));
}

function dedupeKey(entry) {
  return sanitizeEntry(entry).replace(/-/g, ' ');
}

export function extractSuggestFromHtml({ html, mode, maxResults }) {
  const normalizedMode = normalizeMode(mode);
  const source = String(html ?? '');
  const limit = clampMaxResults(maxResults);
  const selectors = selectorsForStage({ mode: normalizedMode, stage: 'suggest' });

  const classCandidates = [];
  for (const selector of selectors.candidateHeadwords) {
    const className = primaryClassFromSelector(selector);
    if (!className) {
      continue;
    }
    const texts = collectClassTexts(source, className);
    for (const text of texts) {
      classCandidates.push({ entry: text, label: text, url: '' });
    }
  }

  const linkCandidates = collectLinkCandidates(source, normalizedMode);
  const merged = [...classCandidates, ...linkCandidates];

  const deduped = [];
  const seen = new Set();
  for (const candidate of merged) {
    let entry;
    try {
      entry = sanitizeEntry(candidate.entry);
    } catch {
      continue;
    }

    const key = dedupeKey(entry);
    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    deduped.push({
      entry,
      label: candidate.label || entry,
      url: candidate.url || buildDefineUrl({ entry, mode: normalizedMode }),
    });

    if (deduped.length >= limit) {
      break;
    }
  }

  return deduped;
}
