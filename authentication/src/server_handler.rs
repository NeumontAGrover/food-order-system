use base64::{Engine, prelude::BASE64_STANDARD};
use http_body_util::{BodyExt, Full, combinators::BoxBody};
use hyper::{Method, Request, Response, StatusCode, body::Bytes};

use crate::postgres_client::PostgresClient;

pub struct ServerInstance {
    postgres: PostgresClient
}

impl ServerInstance {
    pub async fn new() -> ServerInstance {
        let client = match PostgresClient::new().await {
            Ok(client) => client,
            Err(err) => panic!("There was an error connecting to the database {}", err),
        };

        ServerInstance { postgres: client }
    }

    pub async fn serve(&self, req: Request<hyper::body::Incoming>) -> Result<Response<BoxBody<Bytes, hyper::Error>>, hyper::Error> {
        match (req.method(), req.uri().path()) {
            (&Method::GET, "/") | (&Method::GET, "/healthcheck") => self.healthcheck(),
            (&Method::POST, "/register") => self.register(req).await,
            _ => {
                let mut response = Response::new(
                    self.create_message("{\"message\":\"Invalid Endpoint\"}")
                );
                *response.status_mut() = StatusCode::NOT_FOUND;
                Ok(response)
            }
        }
    }
    
    fn healthcheck(&self) -> Result<Response<BoxBody<Bytes, hyper::Error>>, hyper::Error> {
        let mut response = Response::new(
            self.create_message("{\"message\":\"Authentication service is healthy\"}")
        );
        *response.status_mut() = StatusCode::OK;
        Ok(response)
    }
    
    async fn register(&self, req: Request<hyper::body::Incoming>) -> Result<Response<BoxBody<Bytes, hyper::Error>>, hyper::Error> {
        let mut response = Response::new(
            self.create_message("{\"message\":\"User added\"}")
        );
        let status = response.status_mut();
        *status = StatusCode::CREATED;
    
        let body = req.collect().await?.to_bytes();
        let body_json: Option<serde_json::Value> = match serde_json::from_slice(body.as_ref()) {
            Ok(json) => json,
            Err(_) => None,
        };
    
        match body_json {
            Some(user) => 'validate_body: {
                if user["username"].is_null() || user["password"].is_null() {
                    *status = StatusCode::BAD_REQUEST;
                    break 'validate_body;
                }

                let base64_password = user["password"].as_str().unwrap();
                let password = match BASE64_STANDARD.decode(base64_password) {
                    Ok(result) => Some(result),
                    Err(_) => {
                        *status = StatusCode::NOT_ACCEPTABLE;
                        None
                    },
                };
                
                if password.is_none() {
                    break 'validate_body;
                }

                let add_result = self.postgres.add_user(
                    user["username"].as_str().unwrap(),
                    str::from_utf8(password.unwrap().as_slice()).ok().unwrap()
                ).await;

                match add_result {
                    Ok(code) => println!("User was not added to the database ({})", code),
                    Err(err) => {
                        eprintln!("User was not added to the database ({})", err.as_db_error().unwrap().message());
                        *status = StatusCode::INTERNAL_SERVER_ERROR;
                    },
                }
            },
            None => *status = StatusCode::BAD_REQUEST,
        }
    
        match *status {
            StatusCode::CREATED => {}
            StatusCode::BAD_REQUEST => {
                response = Response::new(
                    self.create_message("{\"message\":\"There was a problem parsing the request body\"}")
                );
            },
            StatusCode::NOT_ACCEPTABLE => {
                response = Response::new(
                    self.create_message("{\"message\":\"Could not decode the password. Invalid format\"}")
                );
            },
            _ => {
                response = Response::new(
                    self.create_message("{\"message\":\"An error occurred\"}")
                );
            }
        }
    
        Ok(response)
    }
    
    fn create_message(&self, message: impl Into<Bytes>) -> BoxBody<Bytes, hyper::Error> {
        Full::new(message.into())
            .map_err(|err| match err {})
            .boxed()
    }
}
