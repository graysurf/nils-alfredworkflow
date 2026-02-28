# Google CLI native capability matrix

Status values:

- `usable via generated crate`
- `usable via reqwest fallback`
- `blocked`

## Command capability matrix

| Operation | Status | Primary path | Fallback path | Notes |
| --- | --- | --- | --- | --- |
| `auth credentials set` | `usable via generated crate` | native config + `yup-oauth2` credential handling | N/A | Local config write; no direct Google API call required. |
| `auth credentials list` | `usable via generated crate` | native config + `yup-oauth2` credential handling | N/A | Local config read; deterministic format is native-owned. |
| `auth add` | `usable via reqwest fallback` | `yup-oauth2` installed flow | direct token endpoint exchange via `reqwest` when mode gaps exist | Covers `loopback`, `manual`, and `remote` modes. |
| `auth status` | `usable via generated crate` | native account/default resolution | N/A | Must never emit empty account payload on ambiguity. |
| `auth remove` | `usable via generated crate` | native token store + metadata | N/A | Keyring + local metadata cleanup. |
| `auth alias` | `usable via generated crate` | native alias metadata store | N/A | Alias set/list/unset remains local metadata behavior. |
| `auth manage` | `blocked` | N/A | N/A | Browser manager UI is a Sprint non-goal. Command becomes terminal-native summary/help behavior. |
| `gmail search` | `usable via generated crate` | `google-gmail1` list/query APIs | `reqwest` query fallback if generated gap appears | Primary generated path expected. |
| `gmail get` | `usable via generated crate` | `google-gmail1` message get APIs | `reqwest` fallback if generated gap appears | Supports message retrieval and formats. |
| `gmail send` | `usable via generated crate` | `google-gmail1` send API + `mail-builder` + `mime_guess` | `reqwest` fallback for unsupported edge cases | Native MIME construction required. |
| `gmail thread get` | `usable via generated crate` | `google-gmail1` thread get API | `reqwest` fallback if generated gap appears | |
| `gmail thread modify` | `usable via generated crate` | `google-gmail1` thread modify API | `reqwest` fallback if generated gap appears | |
| `drive ls` | `usable via generated crate` | `google-drive3` file list API | `reqwest` fallback if generated gap appears | |
| `drive search` | `usable via generated crate` | `google-drive3` file list/search query API | `reqwest` fallback if generated gap appears | |
| `drive get` | `usable via generated crate` | `google-drive3` file get API | `reqwest` fallback if generated gap appears | |
| `drive download` | `usable via generated crate` | `google-drive3` media download APIs | `reqwest` fallback for export/content edge cases | |
| `drive upload` | `usable via generated crate` | `google-drive3` create/update upload APIs | `reqwest` fallback for resumable edge cases | |
