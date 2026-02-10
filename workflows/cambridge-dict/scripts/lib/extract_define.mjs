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

function normalizeText(value) {
  return decodeHtmlEntities(String(value ?? '').replace(/<[^>]+>/g, ' '))
    .replace(/\s+/g, ' ')
    .replace(/\s+([,.;:!?])/g, '$1')
    .trim();
}

function primaryClassFromSelector(selector) {
  const classes = [...String(selector).matchAll(/\.([a-zA-Z][\w-]*)/g)].map((match) => match[1]);
  if (classes.length === 0) {
    return '';
  }
  return classes[classes.length - 1];
}

const VOID_TAGS = new Set([
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
]);

function hasExactClassToken(rawClassList, className) {
  return String(rawClassList)
    .split(/\s+/)
    .some((token) => token === className);
}

function isSelfClosingOpenTag(openTag, tagName) {
  return /\/\s*>$/.test(openTag) || VOID_TAGS.has(String(tagName).toLowerCase());
}

function findMatchingCloseIndex(html, tagName, contentStartIndex) {
  const normalizedTagName = String(tagName).toLowerCase();
  if (VOID_TAGS.has(normalizedTagName)) {
    return contentStartIndex;
  }

  const pattern = new RegExp(`<\\/?${escapeRegExp(normalizedTagName)}\\b[^>]*>`, 'gi');
  pattern.lastIndex = contentStartIndex;

  let depth = 1;
  let match;
  while ((match = pattern.exec(html)) !== null) {
    const token = match[0];
    const isClosingTag = token.startsWith('</');
    if (isClosingTag) {
      depth -= 1;
      if (depth === 0) {
        return match.index;
      }
      continue;
    }

    if (!/\/\s*>$/.test(token)) {
      depth += 1;
    }
  }

  return -1;
}

function collectByClass(html, className) {
  const pattern = /<([a-zA-Z][\w:-]*)\b[^>]*\bclass=(['"])([^'"]+)\2[^>]*>/gi;

  const values = [];
  for (const match of html.matchAll(pattern)) {
    const openTag = match[0];
    const tagName = String(match[1]).toLowerCase();
    const rawClassList = match[3];
    if (!hasExactClassToken(rawClassList, className)) {
      continue;
    }
    if (isSelfClosingOpenTag(openTag, tagName)) {
      continue;
    }

    const contentStartIndex = (match.index ?? 0) + openTag.length;
    const contentEndIndex = findMatchingCloseIndex(html, tagName, contentStartIndex);
    if (contentEndIndex < contentStartIndex) {
      continue;
    }

    const normalized = normalizeText(html.slice(contentStartIndex, contentEndIndex));
    if (normalized) {
      values.push(normalized);
    }
  }
  return values;
}

function firstClassText(html, selectors) {
  for (const selector of selectors) {
    const className = primaryClassFromSelector(selector);
    if (!className) {
      continue;
    }
    const values = collectByClass(html, className);
    if (values.length > 0) {
      return values[0];
    }
  }
  return '';
}

function manyClassTexts(html, selectors, limit) {
  const output = [];
  const seen = new Set();

  for (const selector of selectors) {
    const className = primaryClassFromSelector(selector);
    if (!className) {
      continue;
    }
    for (const text of collectByClass(html, className)) {
      const normalized = text.toLowerCase();
      if (seen.has(normalized)) {
        continue;
      }
      seen.add(normalized);
      output.push(text);
      if (output.length >= limit) {
        return output;
      }
    }
  }

  return output;
}

function absolutizeUrl(rawValue) {
  const value = String(rawValue ?? '').trim();
  if (!value) {
    return '';
  }
  if (/^https?:\/\//i.test(value)) {
    return value;
  }
  if (value.startsWith('/')) {
    return `${CAMBRIDGE_BASE_URL}${value}`;
  }
  return `${CAMBRIDGE_BASE_URL}/${value}`;
}

function findCanonicalUrl(html) {
  const linkMatch = html.match(/<link\b[^>]*rel=(['"])canonical\1[^>]*href=(['"])([^'"]+)\2[^>]*>/i);
  if (linkMatch && linkMatch[3]) {
    return absolutizeUrl(linkMatch[3]);
  }

  const metaMatch = html.match(/<meta\b[^>]*property=(['"])og:url\1[^>]*content=(['"])([^'"]+)\2[^>]*>/i);
  if (metaMatch && metaMatch[3]) {
    return absolutizeUrl(metaMatch[3]);
  }

  const anchorMatch = html.match(/<a\b[^>]*href=(['"])([^'"]*\/dictionary\/[^'"]*)\1/i);
  if (anchorMatch && anchorMatch[2]) {
    return absolutizeUrl(anchorMatch[2]);
  }

  return '';
}

function fallbackHeadword({ html, entry }) {
  const titleMatch = html.match(/<title>([\s\S]*?)<\/title>/i);
  if (titleMatch) {
    const normalized = normalizeText(titleMatch[1]);
    if (normalized) {
      const first = normalized.split('|')[0].trim();
      if (first) {
        return first;
      }
    }
  }
  return entry;
}

export function extractDefineFromHtml({ html, mode, entry }) {
  const normalizedMode = normalizeMode(mode);
  const normalizedEntry = sanitizeEntry(entry);
  const source = String(html ?? '');
  const selectors = selectorsForStage({ mode: normalizedMode, stage: 'define' });

  const headword = firstClassText(source, selectors.headword) || fallbackHeadword({ html: source, entry: normalizedEntry });
  const partOfSpeech = firstClassText(source, selectors.partOfSpeech);
  const phonetics = manyClassTexts(source, selectors.phonetics, 4);
  const definitions = manyClassTexts(source, selectors.definitions, 8);

  const url = findCanonicalUrl(source) || buildDefineUrl({ entry: normalizedEntry, mode: normalizedMode });

  return {
    headword,
    partOfSpeech,
    phonetics,
    definitions,
    url,
  };
}
