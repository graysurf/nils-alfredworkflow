export const ERROR_CODES = Object.freeze({
  ANTI_BOT: 'anti_bot',
  COOKIE_WALL: 'cookie_wall',
  TIMEOUT: 'timeout',
  PARSE_ERROR: 'parse_error',
  INVALID_ARGS: 'invalid_args',
  NOT_IMPLEMENTED: 'not_implemented',
  UNKNOWN: 'unknown',
});

function normalizeMessage(error) {
  if (!error) {
    return '';
  }
  if (typeof error === 'string') {
    return error.trim();
  }
  return String(error.message ?? error).trim();
}

export function classifyScraperError(error) {
  const message = normalizeMessage(error);
  const lower = message.toLowerCase();

  if (!message) {
    return {
      code: ERROR_CODES.UNKNOWN,
      message: 'unknown scraper failure',
      hint: 'retry later',
      retriable: false,
    };
  }

  if (
    lower.includes('query must not be empty') ||
    lower.includes('invalid type token') ||
    lower.includes('unknown argument')
  ) {
    return {
      code: ERROR_CODES.INVALID_ARGS,
      message,
      hint: 'check CLI arguments and type token values',
      retriable: false,
    };
  }

  if (lower.includes('not implemented') || lower.includes('disabled by default')) {
    return {
      code: ERROR_CODES.NOT_IMPLEMENTED,
      message,
      hint: 'keep API-first path; enable scraper only after rollout gates',
      retriable: false,
    };
  }

  if (lower.includes('timeout') || lower.includes('timed out')) {
    return {
      code: ERROR_CODES.TIMEOUT,
      message,
      hint: 'increase timeout and retry',
      retriable: true,
    };
  }

  if (lower.includes('cloudflare') || lower.includes('captcha') || lower.includes('cf-challenge')) {
    return {
      code: ERROR_CODES.ANTI_BOT,
      message,
      hint: 'anti-bot challenge detected; retry later',
      retriable: true,
    };
  }

  if (lower.includes('cookie') && (lower.includes('consent') || lower.includes('enable'))) {
    return {
      code: ERROR_CODES.COOKIE_WALL,
      message,
      hint: 'open Bangumi in browser and complete cookie flow, then retry',
      retriable: true,
    };
  }

  if (lower.includes('parse') || lower.includes('selector')) {
    return {
      code: ERROR_CODES.PARSE_ERROR,
      message,
      hint: 'update parser selectors and retry',
      retriable: false,
    };
  }

  return {
    code: ERROR_CODES.UNKNOWN,
    message,
    hint: 'retry later',
    retriable: false,
  };
}

export function asStructuredError({ stage = 'unknown', error }) {
  return {
    ok: false,
    stage,
    error: classifyScraperError(error),
  };
}
