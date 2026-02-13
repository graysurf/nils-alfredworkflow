# open-project Troubleshooting

Reference: [ALFRED_WORKFLOW_DEVELOPMENT.md](../../ALFRED_WORKFLOW_DEVELOPMENT.md)

## Quick operator checks

1. Confirm latest package was installed:
   - `scripts/workflow-pack.sh --id open-project --install`
2. Confirm you are testing the current installed workflow copy:
   - Resolve installed path by `bundleid=com.graysurf.open-project`.
3. Inspect runtime node config in installed `info.plist`:
   - Script nodes should use external script mode (`config.type=8`) with expected `scriptfile`.
4. Run scripts directly from the installed workflow directory:
   - `./scripts/script_filter.sh "" | jq '.items | length'`
5. Verify action-chain payload handoff:
   - Confirm `Script Filter -> Record Usage -> Open` keeps path args without trailing newline.

## Common failures and actions

| Symptom in Alfred | Likely cause | Action |
| --- | --- | --- |
| Looks successful, but deleting old workflow breaks behavior. | Validation accidentally hit an old installed workflow copy. | Locate installed workflow by `bundleid` before testing and verify target path explicitly. |
| Script Filter finishes with no items. | `scriptfile` is set but node `config.type` stayed `0` (inline mode). | Set Script Filter / Action node `config.type=8` for external script mode, then re-pack/reinstall. |
| Error: `No such file or directory: /Users/.../Application` | Command path with spaces was unquoted (`$workflow_cli ...`). | Quote executable path (`"$workflow_cli" ...`) and verify JSON output from installed script. |
| Repo list works, but Enter open fails with `not a directory`. | Action chain passed path with trailing newline to open action. | Ensure `record_usage` emits path without trailing newline; keep strict directory check in open action. |
| Script Filter failure shows blank UI. | Failure path only writes stderr and returns no Alfred JSON response. | Add fallback error item JSON in `script_filter.sh` so failures still render in Alfred. |
| `"workflow-cli" Not Opened` / `Apple could not verify ...` | Packaged binary carries `com.apple.quarantine`; Gatekeeper blocks execution. | Clear quarantine on installed workflow package (or rely on runtime best-effort cleanup) and retry. |

### Installed-workflow debug commands

```bash
# 1) Find installed workflow directory by bundle id
for p in "$HOME"/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows/*/info.plist; do
  [ -f "$p" ] || continue
  bid=$(plutil -extract bundleid raw -o - "$p" 2>/dev/null || true)
  [ "$bid" = "com.graysurf.open-project" ] && echo "$(dirname "$p")"
done

# 2) Inspect runtime script node config
plutil -convert json -o - "$WORKFLOW_DIR/info.plist" \
  | jq '.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | {uid, config: {type:.config.type, scriptfile:.config.scriptfile}}'

# 3) Execute installed script directly
cd "$WORKFLOW_DIR"
./scripts/script_filter.sh "" | jq '.items | length'
```

### Icon setup

Alfred has two different icon layers. If icon behavior looks inconsistent, verify which layer you are changing.

#### Workflow object icon (Script Filter node icon in Alfred canvas)

- Rule: place a PNG at workflow package root with filename `<OBJECT_UID>.png`.
- Example in this repo: `8F3399E3-951A-4DC0-BC7D-CFA83C1E1F76.png` is the `github` Script Filter object icon.

Find Script Filter object UIDs:

```bash
plutil -convert json -o - "$WORKFLOW_DIR/info.plist" \
  | jq -r '.objects[] | select(.type=="alfred.workflow.input.scriptfilter") | "\(.config.keyword)\t\(.uid)"'
```

Add/replace one object icon manually (installed workflow):

```bash
cp /path/to/github-icon.png "$WORKFLOW_DIR/<OBJECT_UID>.png"
```

Project source location (so packaging keeps it):

- Put file at `workflows/open-project/src/<OBJECT_UID>.png`
- `scripts/workflow-pack.sh` copies `src/*.png` to package root.

#### Script Filter result-item icon (icon shown for each row in result list)

- Rule: emit `icon.path` in Script Filter JSON item.
- For open-project GitHub mode, this is handled by:
  - `workflows/open-project/scripts/script_filter_github.sh`
  - `workflow-cli script-filter --mode github`
  - feedback item icon path: `assets/icon-github.png`

Quick check:

```bash
cd "$WORKFLOW_DIR"
./scripts/script_filter_github.sh "" | jq -r '.items[0].icon.path'
```

### macOS Gatekeeper fix

If installed release workflow shows `"workflow-cli" Not Opened`, remove quarantine on the installed workflow package:

```bash
WORKFLOW_DIR="$(for p in "$HOME"/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows/*/info.plist; do
  [ -f "$p" ] || continue
  bid="$(plutil -extract bundleid raw -o - "$p" 2>/dev/null || true)"
  [ "$bid" = "com.graysurf.open-project" ] && dirname "$p"
done | head -n1)"

[ -n "$WORKFLOW_DIR" ] || { echo "workflow not found"; exit 1; }
xattr -dr com.apple.quarantine "$WORKFLOW_DIR"
echo "ok: removed quarantine from $WORKFLOW_DIR"
```

Notes:

- Runtime scripts also perform best-effort quarantine cleanup on `bin/workflow-cli` automatically.
- This issue only applies to macOS Gatekeeper; Linux runners are unaffected.

## Validation

When touching workflow runtime wiring (`info.plist.template` or script chain), always run:

- `scripts/workflow-lint.sh`
- `bash workflows/open-project/tests/smoke.sh`
- `scripts/workflow-pack.sh --id open-project --install`

## Rollback guidance

Use this when open-project behavior regresses and a fast fallback is required.

1. Stop rollout of new `open-project` artifacts (pause release/distribution link).
2. Revert open-project changeset(s), including:
   - `workflows/open-project/`
   - `crates/workflow-cli/`
   - related docs updates tied to open-project rollout.
3. Rebuild and validate rollback state:
   - `scripts/workflow-lint.sh`
   - `scripts/workflow-test.sh`
   - `scripts/workflow-pack.sh --all`
4. Publish known-good artifact set and post operator notice.
