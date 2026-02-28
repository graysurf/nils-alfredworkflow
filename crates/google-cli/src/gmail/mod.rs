#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GmailExecutionPath {
    GeneratedCrate,
    ReqwestFallback,
}
