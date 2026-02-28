#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NativeTransport {
    GeneratedCrate,
    ReqwestFallback,
}
