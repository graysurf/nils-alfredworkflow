use std::fs;
use std::path::PathBuf;

use tempfile::tempdir;
use workflow_readme_cli::{ConvertRequest, ErrorKind, convert};

const PLIST_TEMPLATE: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>readme</key>
  <string>placeholder</string>
</dict>
</plist>
"#;

#[test]
fn detects_and_copies_local_image_assets() {
    let temp = tempdir().expect("create temp dir");
    let workflow_root = temp.path().join("workflow");
    let stage_dir = temp.path().join("stage");
    let plist = temp.path().join("info.plist");

    fs::create_dir_all(workflow_root.join("assets")).expect("create assets dir");
    fs::write(
        workflow_root.join("README.md"),
        "# Demo\n\n![shot](assets/screenshot.png)\n",
    )
    .expect("write readme");
    fs::write(workflow_root.join("assets/screenshot.png"), b"png-bytes").expect("write image");
    fs::write(&plist, PLIST_TEMPLATE).expect("write plist");

    let output = convert(&ConvertRequest {
        workflow_root: workflow_root.clone(),
        readme_source: PathBuf::from("README.md"),
        stage_dir: stage_dir.clone(),
        plist: plist.clone(),
        dry_run: false,
    })
    .expect("convert should succeed");

    assert_eq!(
        output.copied_assets,
        vec![PathBuf::from("assets/screenshot.png")]
    );
    assert_eq!(
        fs::read(stage_dir.join("assets/screenshot.png")).expect("staged image must exist"),
        b"png-bytes"
    );

    let injected_plist = fs::read_to_string(plist).expect("read updated plist");
    assert!(injected_plist.contains("![shot](assets/screenshot.png)"));
}

#[test]
fn rejects_remote_image_urls() {
    let temp = tempdir().expect("create temp dir");
    let workflow_root = temp.path().join("workflow");
    let stage_dir = temp.path().join("stage");
    let plist = temp.path().join("info.plist");

    fs::create_dir_all(&workflow_root).expect("create workflow dir");
    fs::write(
        workflow_root.join("README.md"),
        "# Demo\n\n![shot](https://example.com/screenshot.png)\n",
    )
    .expect("write readme");
    fs::write(&plist, PLIST_TEMPLATE).expect("write plist");

    let error = convert(&ConvertRequest {
        workflow_root,
        readme_source: PathBuf::from("README.md"),
        stage_dir,
        plist,
        dry_run: false,
    })
    .expect_err("remote image should be rejected");

    assert_eq!(error.kind(), ErrorKind::User);
    assert_eq!(error.code(), "user.remote_image_not_allowed");
}
