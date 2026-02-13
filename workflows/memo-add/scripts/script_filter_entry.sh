#!/usr/bin/env bash
set -euo pipefail

# mm is command-entry only. Query text is intentionally ignored.
cat <<'JSON'
{"items":[
  {
    "title":"Memo Commands",
    "subtitle":"Use one keyword below",
    "valid":false
  },
  {
    "title":"Recent memos",
    "subtitle":"Use mmr (or mmr <id>)",
    "autocomplete":"r ",
    "valid":false
  },
  {
    "title":"Add memo",
    "subtitle":"Use mma <text>",
    "autocomplete":"a ",
    "valid":false
  },
  {
    "title":"Update memo",
    "subtitle":"Use mmu (or mmu <item_id> <text>)",
    "autocomplete":"u ",
    "valid":false
  },
  {
    "title":"Delete memo",
    "subtitle":"Use mmd (or mmd <item_id>)",
    "autocomplete":"d ",
    "valid":false
  },
  {
    "title":"Copy memo",
    "subtitle":"Use mmc (or mmc <item_id>)",
    "autocomplete":"c ",
    "valid":false
  },
  {
    "title":"Search memo",
    "subtitle":"Use mmq <query>",
    "autocomplete":"q ",
    "valid":false
  }
]}
JSON
