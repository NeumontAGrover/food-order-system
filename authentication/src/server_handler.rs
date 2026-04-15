use http_body_util::{BodyExt, Full, combinators::BoxBody};
use hyper::{Method, Request, Response, StatusCode, body::Bytes};

pub async fn serve(req: Request<hyper::body::Incoming>) -> Result<Response<BoxBody<Bytes, hyper::Error>>, hyper::Error> {
    match (req.method(), req.uri().path()) {
        (&Method::GET, "/") | (&Method::GET, "/healthcheck") => healthcheck(),
        _ => {
            let mut response = Response::new(
                create_message("{\"message\":\"Invalid Endpoint\"}")
            );
            *response.status_mut() = StatusCode::NOT_FOUND;
            Ok(response)
        }
    }
}

fn healthcheck() -> Result<Response<BoxBody<Bytes, hyper::Error>>, hyper::Error> {
    let mut response = Response::new(
        create_message("{\"message\":\"Authentication service is healthy\"}")
    );
    *response.status_mut() = StatusCode::OK;
    Ok(response)
}

fn create_message<T: Into<Bytes>>(message: T) -> BoxBody<Bytes, hyper::Error> {
    Full::new(message.into())
        .map_err(|err| match err {})
        .boxed()
}
