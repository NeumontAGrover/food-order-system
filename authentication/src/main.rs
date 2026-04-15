use std::net::SocketAddr;

use hyper::{server::conn::http1, service::service_fn};
use hyper_util::rt::TokioIo;
use tokio::net::{TcpListener, TcpStream};

mod server_handler;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let address = SocketAddr::from(([127, 0, 0, 1], 32456));
    let listener = TcpListener::bind(address).await?;

    loop {
        let (stream, _) = listener.accept().await?;

        let io = TokioIo::new(stream);
        tokio::task::spawn(serve_request(io));
    }
}

async fn serve_request(io: TokioIo<TcpStream>) {
    if let Err(err) = http1::Builder::new()
        .serve_connection(io, service_fn(server_handler::serve))
        .await
    {
        eprintln!("Could not serve the connection ({:?})", err);
    }
}
