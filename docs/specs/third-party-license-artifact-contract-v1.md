# Third-Party License Artifact Contract v1

> Status: superseded-by [`third-party-artifacts-contract-v1.md`](third-party-artifacts-contract-v1.md)

## Forwarding notice

This file previously narrowed the license-only generation rules for `THIRD_PARTY_LICENSES.md`. The canonical
contract now covers both `THIRD_PARTY_LICENSES.md` and `THIRD_PARTY_NOTICES.md` from a single specification:

- [`third-party-artifacts-contract-v1.md`](third-party-artifacts-contract-v1.md)

Use the canonical contract for:

- generator entrypoint commands (`scripts/generate-third-party-artifacts.sh --write` / `--check`),
- mandatory section order and table schemas for both artifacts,
- input source list and deterministic rendering rules,
- failure semantics for both `--write` and `--check`.

No new content lives here. This stub remains only so existing external links continue to resolve; please
update bookmarks to point at the canonical contract above.
