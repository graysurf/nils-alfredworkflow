# Market CLI Contract

## Purpose

This document defines the command and JSON output contract for the `market-cli` capability.
Scope includes market data retrieval (`fx`, `crypto`) and Alfred-facing expression output (`expr`).

## Command Contract

### FX

- Command:
  - `market-cli fx --base <ISO4217> --quote <ISO4217> --amount <decimal>`
- Required flags:
  - `--base`: base fiat currency (for example `USD`)
  - `--quote`: quote fiat currency (for example `JPY`)
  - `--amount`: amount to convert, must be a positive decimal

### Crypto

- Command:
  - `market-cli crypto --base <SYMBOL> --quote <SYMBOL> --amount <decimal>`
- Required flags:
  - `--base`: base asset symbol (for example `BTC`)
  - `--quote`: quote symbol (for example `USD`)
  - `--amount`: amount to convert, must be a positive decimal

### Expr

- Command:
  - `market-cli expr --query "<expression>" [--default-fiat <ISO4217>]`
- Required flags:
  - `--query`: expression string
- Optional flags:
  - `--default-fiat`: 3-letter fiat code used when query omits `to <fiat>` (default `USD`)
- Expression behavior:
  - Numeric-only terms -> one Alfred item with final result (`1+5` -> `6`; supports `+ - * /`)
  - Asset-only terms -> unit-price items for each unique asset, then total item
  - Mixed asset and numeric terms -> user error
  - Asset expressions with unsupported operators (`*`, `/`) -> user error

### Exit Behavior

- Exit code `0`: success (stdout prints exactly one JSON object)
- Exit code `2`: user/input error (invalid symbol format, invalid expression, non-positive amount, missing required flags)
- Exit code `1`: runtime/provider/cache error without usable fallback

## Provider and Cache Policy

- No API key is required for any command path.
- FX provider stack:
  - `Frankfurter` (single provider)
  - Fixed TTL: `86400` seconds (`24h`)
- Crypto provider stack:
  - Primary: `Coinbase`
  - Fallback: `Kraken`
  - Fixed TTL: `300` seconds (`5m`)
- Freshness states:
  - `live`: freshly fetched from provider
  - `cache_fresh`: served from cache within TTL
  - `cache_stale_fallback`: provider failed, stale cache returned as fallback
- Retry/backoff policy:
  - bounded retries only (`max_attempts = 3`)
  - exponential backoff from base `200ms` (200ms, 400ms)
  - retryable: transport failures and HTTP `429`/`5xx`
  - non-retryable: invalid payload and unsupported pair errors (fail fast)

## Output JSON Schema

Successful output is one JSON object with this shape:

```json
{
  "kind": "fx|crypto",
  "base": "USD",
  "quote": "JPY",
  "amount": "100",
  "unit_price": "31.25",
  "converted": "3125",
  "provider": "frankfurter",
  "fetched_at": "2026-02-10T09:30:12Z",
  "cache": {
    "status": "live|cache_fresh|cache_stale_fallback",
    "key": "fx-usd-twd",
    "ttl_secs": 86400,
    "age_secs": 0
  }
}
```

For `expr`, successful output is Alfred Script Filter JSON:

```json
{
  "items": [
    {
      "title": "1 BTC = 3200000 JPY",
      "subtitle": "provider: coinbase · freshness: live",
      "arg": "3200000 JPY",
      "valid": true
    },
    {
      "title": "Total = 12800000 JPY",
      "subtitle": "Formula: 1*3200000(BTC) + 3*3200000(BTC) = 12800000 JPY",
      "arg": "12800000 JPY",
      "valid": true
    }
  ]
}
```

Field requirements:

| Field | Type | Notes |
| --- | --- | --- |
| `kind` | string | `fx` or `crypto` |
| `base` | string | Uppercase symbol |
| `quote` | string | Uppercase symbol |
| `amount` | string | Requested conversion amount (normalized decimal string) |
| `unit_price` | string | Price of 1 `base` in `quote` (normalized decimal string) |
| `converted` | string | `amount * unit_price` (normalized decimal string) |
| `provider` | string | Final provider used for returned data |
| `fetched_at` | string | RFC3339 UTC timestamp of source data |
| `cache` | object | Cache metadata block |
| `cache.status` | string | `live`, `cache_fresh`, or `cache_stale_fallback` |
| `cache.key` | string | Stable cache key (`<kind>-<base>-<quote>`) |
| `cache.ttl_secs` | number | Fixed per market kind (`86400` or `300`) |
| `cache.age_secs` | number | Cache age in seconds at response time |

## `script_filter.sh` Integration Notes

- `market-expression` workflow calls `market-cli expr` directly and passes through Alfred JSON.
- For non-zero exits, script filter should render one fallback item with `valid: false`.

Minimal shell examples:

```bash
# FX
json="$(market-cli fx --base USD --quote JPY --amount 100)"
JSON="$json" python3 - <<'PY'
import json, os
data = json.loads(os.environ["JSON"])
print(data["converted"])
PY

# Crypto
json="$(market-cli crypto --base BTC --quote USD --amount 0.5)"
JSON="$json" python3 - <<'PY'
import json, os
data = json.loads(os.environ["JSON"])
print(f'{data["provider"]} / {data["cache"]["status"]}')
PY

# Expr (Alfred JSON passthrough)
market-cli expr --query "1 btc + 3 eth to jpy" --default-fiat USD
```
