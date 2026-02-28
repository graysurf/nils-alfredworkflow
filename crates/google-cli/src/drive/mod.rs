#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DriveExecutionPath {
    GeneratedCrate,
    ReqwestFallback,
}
