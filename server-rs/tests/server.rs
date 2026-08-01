use std::net::TcpStream;

#[test]
fn starts_accepts_stops_with_stable_peer_id() {
    let dir = std::env::temp_dir().join(format!("patchwork-server-test-{}", std::process::id()));
    let data_dir = dir.to_string_lossy().into_owned();

    let port = patchwork_server::server_start(data_dir.clone(), 0).unwrap();
    assert_ne!(port, 0);
    let peer_id = patchwork_server::server_peer_id().unwrap();
    assert_eq!(patchwork_server::server_port(), Some(port));

    TcpStream::connect(("127.0.0.1", port)).expect("server should accept connections");

    assert!(matches!(
        patchwork_server::server_start(data_dir.clone(), 0),
        Err(patchwork_server::ServerError::AlreadyRunning)
    ));

    patchwork_server::server_stop();
    assert_eq!(patchwork_server::server_port(), None);

    let port2 = patchwork_server::server_start(data_dir, 0).unwrap();
    let peer_id2 = patchwork_server::server_peer_id().unwrap();
    patchwork_server::server_stop();

    assert_eq!(peer_id, peer_id2);
    assert_ne!(port2, 0);

    std::fs::remove_dir_all(dir).ok();
}
