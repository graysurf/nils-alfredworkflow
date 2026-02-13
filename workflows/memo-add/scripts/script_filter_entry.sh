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
    "autocomplete":"mmr",
    "valid":false
  },
  {
    "title":"Add memo",
    "subtitle":"Use mma <text>",
    "autocomplete":"mma ",
    "valid":false
  },
  {
    "title":"Update memo",
    "subtitle":"Use mmu (or mmu <item_id> <text>)",
    "autocomplete":"mmu ",
    "valid":false
  },
  {
    "title":"Delete memo",
    "subtitle":"Use mmd (or mmd <item_id>)",
    "autocomplete":"mmd ",
    "valid":false
  },
  {
    "title":"Copy memo",
    "subtitle":"Use mmc (or mmc <item_id>)",
    "autocomplete":"mmc ",
    "valid":false
  }
]}
JSON
