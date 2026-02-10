import { normalizeMode } from './cambridge_routes.mjs';

const BASE_SELECTORS = Object.freeze({
  suggest: Object.freeze({
    candidateHeadwords: Object.freeze([
      '.search_results .h .hw',
      '.entry-body .headword',
      '.entry-body .hw',
      '.entry .headword',
      '.di-title .hw',
      '.phrase-title .hw',
    ]),
    candidateLinks: Object.freeze([
      '.search_results .entry-link',
      '.entry-body a[href*="/dictionary/"]',
      '.di-title a[href*="/dictionary/"]',
    ]),
  }),
  define: Object.freeze({
    headword: Object.freeze([
      '.entry-body .headword',
      '.head .hw',
      '.di-title .hw',
      'h1 .hw',
    ]),
    partOfSpeech: Object.freeze([
      '.entry-body .pos',
      '.posgram .pos',
      '.pos-header .pos',
    ]),
    phonetics: Object.freeze([
      '.entry-body .ipa',
      '.pron .ipa',
      '.dpron-i .ipa',
    ]),
    definitions: Object.freeze([
      '.entry-body .def',
      '.sense-body .def',
      '.def-block .def',
      '.def-body .def',
      '.def.ddef_d',
    ]),
    canonicalUrl: Object.freeze([
      'link[rel="canonical"]',
      'meta[property="og:url"]',
      'a[href*="/dictionary/"]',
    ]),
  }),
});

const MODE_OVERRIDES = Object.freeze({
  english: Object.freeze({}),
  'english-chinese-traditional': Object.freeze({
    define: Object.freeze({
      definitions: Object.freeze([
        '.entry-body .trans',
        '.entry-body .def',
        '.sense-body .trans',
        '.def-body .trans',
      ]),
    }),
  }),
});

function mergeUnique(baseList, overrideList) {
  const merged = [...(overrideList || []), ...(baseList || [])];
  return [...new Set(merged)];
}

function mergeStage(baseStage, overrideStage) {
  const result = {};
  const keys = new Set([...Object.keys(baseStage || {}), ...Object.keys(overrideStage || {})]);
  for (const key of keys) {
    result[key] = mergeUnique(baseStage?.[key], overrideStage?.[key]);
  }
  return result;
}

export function selectorsForMode(mode) {
  const normalizedMode = normalizeMode(mode);
  const override = MODE_OVERRIDES[normalizedMode] || {};
  return {
    suggest: mergeStage(BASE_SELECTORS.suggest, override.suggest),
    define: mergeStage(BASE_SELECTORS.define, override.define),
  };
}

export function selectorsForStage({ mode, stage }) {
  const selectorSet = selectorsForMode(mode);
  if (!selectorSet[stage]) {
    throw new Error(`unknown stage: ${stage}`);
  }
  return selectorSet[stage];
}

export { BASE_SELECTORS, MODE_OVERRIDES };
