use beamlet_message_zenoh::{Error, Limits, Transport};
use std::{net::TcpListener, time::Duration};
use tokio::time::timeout;

async fn listener(inbox: &str, limits: Limits) -> (Transport, String) {
    for _ in 0..5 {
        let socket = TcpListener::bind("127.0.0.1:0").unwrap();
        let endpoint = format!("tcp/{}", socket.local_addr().unwrap());
        drop(socket);
        if let Ok(transport) = Transport::listen(&endpoint, inbox, limits).await {
            return (transport, endpoint);
        }
    }
    panic!("listener must bind after bounded port-selection retries");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn two_static_sessions_exchange_bytes_in_both_directions() {
    let (authority, endpoint) = listener("beamlet/test/authority", Limits::default()).await;
    let work = Transport::connect(&endpoint, "beamlet/test/work", Limits::default())
        .await
        .expect("work session must connect");
    let to_work = authority.sender("beamlet/test/work").await.unwrap();
    let to_authority = work.sender("beamlet/test/authority").await.unwrap();
    timeout(Duration::from_secs(10), async {
        to_work.wait_for_receiver().await.unwrap();
        to_authority.wait_for_receiver().await.unwrap();
        to_work.send(b"dispatch".to_vec()).await.unwrap();
        assert_eq!(work.recv().await.unwrap(), b"dispatch");
        to_authority.send(b"report".to_vec()).await.unwrap();
        assert_eq!(authority.recv().await.unwrap(), b"report");
    })
    .await
    .expect("explicit subscriber matching must complete without readiness sleeps");
}

#[test]
fn zero_limits_are_rejected_before_opening_a_session() {
    assert!(matches!(Limits::new(0, 1), Err(Error::InvalidLimits)));
    assert!(matches!(Limits::new(1, 0), Err(Error::InvalidLimits)));
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn byte_limits_apply_to_sends_and_receives_without_poisoning_the_session() {
    let (authority, endpoint) =
        listener("beamlet/test/budget/authority", Limits::new(16, 1).unwrap()).await;
    let work = Transport::connect(
        &endpoint,
        "beamlet/test/budget/work",
        Limits::new(8, 1).unwrap(),
    )
    .await
    .unwrap();
    let sender = authority.sender("beamlet/test/budget/work").await.unwrap();
    timeout(Duration::from_secs(10), async {
        sender.wait_for_receiver().await.unwrap();
        assert!(matches!(
            sender.send(vec![0; 17]).await,
            Err(Error::MessageTooLarge)
        ));
        sender.send(vec![1; 9]).await.unwrap();
        assert!(matches!(work.recv().await, Err(Error::MessageTooLarge)));
        sender.send(vec![2; 8]).await.unwrap();
        assert_eq!(work.recv().await.unwrap(), vec![2; 8]);
    })
    .await
    .expect("byte-budget checks must not stall the connection");
}
