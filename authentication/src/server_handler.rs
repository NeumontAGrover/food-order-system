use base64::{Engine, prelude::BASE64_STANDARD};
use http_body_util::{BodyExt, Full, combinators::BoxBody};
use hyper::{Method, Request, Response, StatusCode, body::Bytes};

use crate::user_db;

pub async fn serve(req: Request<hyper::body::Incoming>) -> Result<Response<BoxBody<Bytes, hyper::Error>>, hyper::Error> {
    if let Err(_) = user_db::connect().await {
        let mut response = Response::new(create_message("{\"message\":\"Could not connect to database\"}"));
        *response.status_mut() = StatusCode::INTERNAL_SERVER_ERROR;
        return Ok(response);
    }

    match (req.method(), req.uri().path()) {
        (&Method::GET, "/") | (&Method::GET, "/healthcheck") => healthcheck(),
        (&Method::POST, "/register") => register(req).await,
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

async fn register(req: Request<hyper::body::Incoming>) -> Result<Response<BoxBody<Bytes, hyper::Error>>, hyper::Error> {
    let mut response = Response::new(
        create_message("{\"message\":\"User added\"}")
    );
    let status = response.status_mut();
    *status = StatusCode::CREATED;

    let body = req.collect().await?.to_bytes();
    let body_json: Option<serde_json::Value> = match serde_json::from_slice(body.as_ref()) {
        Ok(json) => json,
        Err(_) => None,
    };

    match body_json {
        Some(user) => {
            if user["username"].is_null() || user["password"].is_null() {
                *status = StatusCode::BAD_REQUEST;
            } else {
                let base64_password = user["password"].as_str().unwrap();
                let password: Option<Vec<u8>> = match BASE64_STANDARD.decode(base64_password) {
                    Ok(result) => Some(result),
                    Err(_) => {
                        *status = StatusCode::NOT_ACCEPTABLE;
                        None
                    },
                };
            }
        },
        None => *status = StatusCode::BAD_REQUEST,
    }

    match *status {
        StatusCode::CREATED => {}
        StatusCode::BAD_REQUEST => {
            response = Response::new(
                create_message("{\"message\":\"There was a problem parsing the request body\"}")
            );
        },
        StatusCode::NOT_ACCEPTABLE => {
            response = Response::new(
                create_message("{\"message\":\"Could not decode the password. Invalid format\"}")
            );
        },
        _ => {
            response = Response::new(
                create_message("{\"message\":\"An error occurred\"}")
            );
        }
    }

    Ok(response)
}

fn create_message(message: impl Into<Bytes>) -> BoxBody<Bytes, hyper::Error> {
    Full::new(message.into())
        .map_err(|err| match err {})
        .boxed()
}
