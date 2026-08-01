use std::net::TcpStream;

#[test]
fn starts_accepts_stops_with_stable_peer_id() {
    let dir = std::env::temp_dir().join(format!("Patchwork-server-test-{}", std::process::id()));
    let data_dir = dir.to_string_lossy().into_owned();

    let port = Patchwork_server::server_start(data_dir.clone(), 0).unwrap();
    assert_ne!(port, 0);
    let peer_id = Patchwork_server::server_peer_id().unwrap();
    assert_eq!(Patchwork_server::server_port(), Some(port));

    TcpStream::connect(("127.0.0.1", port)).expect("server should accept connections");

    assert!(matches!(
        Patchwork_server::server_start(data_dir.clone(), 0),
        Err(Patchwork_server::ServerError::AlreadyRunning)
    ));

    Patchwork_server::server_stop();
    assert_eq!(Patchwork_server::server_port(), None);

    let port2 = Patchwork_server::server_start(data_dir, 0).unwrap();
    let peer_id2 = Patchwork_server::server_peer_id().unwrap();
    Patchwork_server::server_stop();

    assert_eq!(peer_id, peer_id2);
    assert_ne!(port2, 0);

    std::fs::remove_dir_all(dir).ok();
}
