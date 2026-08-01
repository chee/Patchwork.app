uniffi::setup_scaffolding!();

mod key;

use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::Duration;

use sedimentree_core::depth::CountLeadingZeroBytes;
use subduction_core::nonce_cache::NonceCache;
use subduction_core::peer::id::PeerId;
use subduction_core::policy::open::OpenPolicy;
use subduction_crypto::signer::memory::MemorySigner;
use subduction_redb_storage::RedbStorage;
use subduction_websocket::timeout::FuturesTimerTimeout;
use subduction_websocket::tokio::server::TokioWebSocketServer;
use subduction_websocket::DEFAULT_MAX_MESSAGE_SIZE;

/// Clients connect by service name (discovery mode) rather than needing the
/// server's peer id up front.
const SERVICE_NAME: &str = "Patchwork-local";
const HANDSHAKE_MAX_DRIFT: Duration = Duration::from_secs(600);

type Server = TokioWebSocketServer<
    RedbStorage,
    OpenPolicy,
    MemorySigner,
    CountLeadingZeroBytes,
    FuturesTimerTimeout,
>;

struct Running {
    runtime: tokio::runtime::Runtime,
    server: Server,
    port: u16,
    peer_id: String,
}

static SERVER: Mutex<Option<Running>> = Mutex::new(None);

#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum ServerError {
    #[error("server already running")]
    AlreadyRunning,
    #[error("{0}")]
    Failed(String),
}

fn fail(error: impl std::fmt::Display) -> ServerError {
    ServerError::Failed(error.to_string())
}

/// Starts the sync server on 127.0.0.1. `port` 0 binds an ephemeral port.
/// Returns the actually-bound port.
#[uniffi::export]
pub fn server_start(data_dir: String, port: u16) -> Result<u16, ServerError> {
    let mut guard = SERVER.lock().unwrap();
    if guard.is_some() {
        return Err(ServerError::AlreadyRunning);
    }

    let data_dir = PathBuf::from(data_dir);
    std::fs::create_dir_all(&data_dir).map_err(fail)?;
    let seed = key::load_or_create_seed(&data_dir.join("server.key")).map_err(fail)?;
    let signer = MemorySigner::from_bytes(&seed);
    let peer_id = PeerId::from(signer.verifying_key());

    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .thread_name("subduction-server")
        .build()
        .map_err(fail)?;

    let address: SocketAddr = ([127, 0, 0, 1], port).into();
    let storage = RedbStorage::new(data_dir.join("storage")).map_err(fail)?;
    let server = runtime
        .block_on(Server::setup(
            address,
            FuturesTimerTimeout,
            HANDSHAKE_MAX_DRIFT,
            DEFAULT_MAX_MESSAGE_SIZE,
            signer,
            Some(SERVICE_NAME),
            storage,
            OpenPolicy,
            NonceCache::default(),
            CountLeadingZeroBytes,
        ))
        .map_err(fail)?;

    let bound_port = server.address().port();
    *guard = Some(Running {
        runtime,
        server,
        port: bound_port,
        peer_id: peer_id.to_string(),
    });
    Ok(bound_port)
}

#[uniffi::export]
pub fn server_stop() {
    if let Some(mut running) = SERVER.lock().unwrap().take() {
        running.runtime.block_on(running.server.stop_and_drain());
        running.runtime.shutdown_timeout(Duration::from_secs(3));
    }
}

#[uniffi::export]
pub fn server_port() -> Option<u16> {
    SERVER.lock().unwrap().as_ref().map(|running| running.port)
}

#[uniffi::export]
pub fn server_peer_id() -> Option<String> {
    SERVER.lock().unwrap().as_ref().map(|running| running.peer_id.clone())
}
