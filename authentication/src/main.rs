use std::net::SocketAddr;

use hyper::{server::conn::http1, service::service_fn};
use hyper_util::rt::TokioIo;
use tokio::net::{TcpListener, TcpStream};

use crate::{postgres_client::PostgresClient, server_handler::ServerInstance};

mod server_handler;
mod postgres_client;
mod redis;
mod jwt;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let address = SocketAddr::from(([0, 0, 0, 0], 32456));
    let listener = TcpListener::bind(address).await?;

    match PostgresClient::new().await?.setup_client().await {
        Ok(_) => (),
        Err(err) => panic!("Could not create tables ({})", err.as_db_error().unwrap().message())
    };

    println!("Running the authentication service on http://authentication-service:32456");
    loop {
        let (stream, _) = listener.accept().await?;

        let io = TokioIo::new(stream);
        tokio::task::spawn(serve_request(io));
    }
}

async fn serve_request(io: TokioIo<TcpStream>) {
    if let Err(err) = http1::Builder::new()
        .serve_connection(io, service_fn(|req| async move {
            let mut server_instance = ServerInstance::new().await;
            server_instance.serve(req).await
        }))
        .await
    {
        eprintln!("Could not serve the connection ({:?})", err);
    }
}
