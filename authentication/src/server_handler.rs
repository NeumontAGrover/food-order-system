use std::{time::SystemTime, str};

use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier, password_hash::{SaltString, rand_core::OsRng}};
use base64::{Engine, prelude::BASE64_STANDARD};
use http_body_util::{BodyExt, Full, combinators::BoxBody};
use hyper::{Method, Request, Response, StatusCode, body::Bytes};

use crate::{jwt, postgres_client::{PostgresClient, User}};
use crate::redis::RedisClient;

type ServerResult = Result<Response<BoxBody<Bytes, hyper::Error>>, hyper::Error>;

pub struct ServerInstance {
    postgres: PostgresClient,
    redis: RedisClient,
}

impl ServerInstance {
    pub async fn new() -> ServerInstance {
        let postgres = match PostgresClient::new().await {
            Ok(client) => client,
            Err(err) => panic!("There was an error connecting to the database {}", err),
        };

        let redis = match RedisClient::new().await {
            Ok(client) => client,
            Err(err) => panic!("There was an error connecting to Redis {}", err),
        };

        ServerInstance { postgres, redis }
    }

    pub async fn serve(&mut self, req: Request<hyper::body::Incoming>) -> ServerResult {
        match (req.method(), req.uri().path()) {
            (&Method::GET, "/") | (&Method::GET, "/healthcheck") => self.healthcheck(),
            (&Method::POST, "/register") => self.register(req).await,
            (&Method::POST, "/login") => self.login(req).await,
            (&Method::GET, "/users") => self.get_users(req).await,
            _ => {
                if req.method() == &Method::GET {
                    let segments: Vec<&str> = req.uri().path().split('/').collect();
                    if segments[1].eq("user") {
                        return self.get_user(req).await;
                    }
                } else if req.method() == &Method::PATCH {
                    let segments: Vec<&str> = req.uri().path().split('/').collect();
                    if segments[1].eq("user") {
                        return self.update_user(req).await;
                    }
                } else if req.method() == &Method::DELETE {
                    let segments: Vec<&str> = req.uri().path().split('/').collect();
                    if segments[1].eq("user") {
                        return self.delete_user(req).await;
                    }
                }

                let mut response = Response::new(
                    self.create_message("{\"message\":\"Invalid Endpoint\"}")
                );
                *response.status_mut() = StatusCode::NOT_FOUND;
                Ok(response)
            }
        }
    }
    
    fn healthcheck(&self) -> ServerResult {
        let mut response = Response::new(
            self.create_message("{\"message\":\"Authentication service is healthy\"}")
        );
        *response.status_mut() = StatusCode::OK;
        Ok(response)
    }
    
    async fn register(&mut self, req: Request<hyper::body::Incoming>) -> ServerResult {
        let mut response = Response::new(self.create_message(""));
        let status = response.status_mut();
        *status = StatusCode::CREATED;
    
        let body = req.collect().await?.to_bytes();
        let body_json: Option<serde_json::Value> = match serde_json::from_slice(body.as_ref()) {
            Ok(json) => json,
            Err(_) => None,
        };
    
        let mut postgres_user = User::new();
        match body_json {
            Some(user) => 'validate_body: {
                let required_fields = ["username", "password", "firstName", "lastName"];
                for field in required_fields {
                    if user[field].is_null() {
                        *status = StatusCode::BAD_REQUEST;
                        break 'validate_body;
                    }
                }

                postgres_user.username = String::from(user["username"].as_str().unwrap());
                postgres_user.first_name = String::from(user["firstName"].as_str().unwrap());
                postgres_user.last_name = String::from(user["lastName"].as_str().unwrap());

                let base64_password = user["password"].as_str().unwrap();
                let password = match BASE64_STANDARD.decode(base64_password) {
                    Ok(result) => Some(result),
                    Err(_) => None,
                };
                
                if password.is_none() {
                    *status = StatusCode::NOT_ACCEPTABLE;
                    break 'validate_body;
                }

                let hashed = hash_password(password.unwrap().as_slice());

                let add_result = self.postgres.add_user(&postgres_user, hashed.as_str()).await;
                match add_result {
                    Ok(rows_changed) => println!("Rows added ({})", rows_changed),
                    Err(err) => {
                        eprintln!("User was not added to the database ({})", err.as_db_error().unwrap().message());
                        *status = StatusCode::INTERNAL_SERVER_ERROR;
                    },
                }
            },
            None => *status = StatusCode::BAD_REQUEST,
        }
    
        match *status {
            StatusCode::CREATED => {
                let current_time_ms = SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).unwrap().as_millis();
                let uid = self.postgres.get_user_id(&postgres_user.username).await.unwrap();
                let token = jwt::create_jwt(uid, false, current_time_ms).unwrap();
                let token_ref = token.as_ref();

                match self.redis.add_token(uid, token_ref).await {
                    Ok(()) => println!("Added token to Redis"),
                    Err(err) => eprintln!("Error adding token to Redis ({:?})", err.detail())
                };

                response = Response::new(
                    self.create_message(format!("{{\"token\":\"{}\"}}", token))
                );
            },
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

    async fn login(&mut self, req: Request<hyper::body::Incoming>) -> ServerResult {
        let mut response = Response::new(self.create_message(""));
        let status = response.status_mut();
        *status = StatusCode::OK;

        let body = req.collect().await?.to_bytes();
        let body_json: Option<serde_json::Value> = match serde_json::from_slice(body.as_ref()) {
            Ok(json) => json,
            Err(_) => None,
        };

        let mut username: Option<String> = None;
        let mut base64_password: Option<String> = None;
        match body_json {
            Some(user) => 'validate_body: {
                let required_fields = ["username", "password"];
                for field in required_fields {
                    if user[field].is_null() {
                        *status = StatusCode::BAD_REQUEST;
                        break 'validate_body;
                    }
                }

                username = Some(String::from(user["username"].as_str().unwrap()));
                base64_password = Some(String::from(user["password"].as_str().unwrap()));
            },
            None => *status = StatusCode::BAD_REQUEST,
        }

        let password = match BASE64_STANDARD.decode(base64_password.unwrap()) {
            Ok(result) => Some(result),
            Err(_) => {
                *status = StatusCode::BAD_REQUEST;
                None
            },
        };

        let mut token: Option<String> = None;
        let mut uid: Option<i32> = None;
        let mut hashed_password: Option<String> = None;
        if *status == StatusCode::OK {
            uid = self.postgres.get_user_id(username.as_ref().unwrap().as_ref()).await;
            if uid.is_some() {
                let is_admin = self.postgres.get_is_admin(uid.unwrap()).await;
                let current_time_ms = SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).unwrap().as_millis();
                token = Some(jwt::create_jwt(uid.unwrap(), is_admin, current_time_ms).unwrap());
                hashed_password = self.postgres.get_user_password_hash(uid.unwrap()).await;
            } else {
                *status = StatusCode::NOT_FOUND;
            }
        }

        if *status == StatusCode::OK {
            if hashed_password.is_none() {
                *status = StatusCode::UNAUTHORIZED;
            } else if !verify_password(password.unwrap().as_ref(), hashed_password.unwrap().as_bytes()) {
                *status = StatusCode::UNAUTHORIZED;
            }
        }

        match *status {
            StatusCode::OK => {
                match self.redis.add_token(uid.unwrap(), token.as_ref().unwrap()).await {
                    Ok(()) => println!("Added token to Redis"),
                    Err(err) => eprintln!("Error adding token to Redis ({:?})", err.detail())
                };

                response = Response::new(
                    self.create_message(format!("{{\"token\":\"{}\"}}", token.unwrap()))
                );
            },
            StatusCode::BAD_REQUEST => {
                response = Response::new(
                    self.create_message("{\"message\":\"There was a problem parsing the request body\"}")
                );
            },
            StatusCode::UNAUTHORIZED => {
                response = Response::new(
                    self.create_message("{\"message\":\"The password is incorrect\"}")
                );
            },
            StatusCode::NOT_FOUND => {
                let message = format!("{{\"message\":\"User is not found with username '{}'\"}}", username.unwrap());
                response = Response::new(self.create_message(message));
            },
            _ => {
                response = Response::new(
                    self.create_message("{\"message\":\"An error occurred\"}")
                );
            }
        }

        Ok(response)
    }

    pub async fn get_users(&mut self, req: Request<hyper::body::Incoming>) -> ServerResult {
        let mut response = Response::new(self.create_message(""));
        let status = response.status_mut();
        *status = StatusCode::OK;

        let token = self.get_token_from_request(&req);
        
        match token {
            Some(token) => {
                let claims = match jwt::decode_jwt(token.as_ref()) {
                    Ok(claims) => Some(claims),
                    Err(_) => {
                        *status = StatusCode::FORBIDDEN;
                        None
                    },
                };
                
                match claims {
                    Some(claims) => {
                        let is_expired = self.redis.is_token_expired(claims.uid).await; 
                        println!("Current token, (expired: {}): {:?}", is_expired, claims);
                        if !claims.admin || is_expired {
                            *status = StatusCode::UNAUTHORIZED
                        }
                    },
                    None => *status = StatusCode::INTERNAL_SERVER_ERROR,
                }
            }
            None => *status = StatusCode::UNAUTHORIZED,
        }

        match *status {
            StatusCode::OK => {
                let all_users = self.postgres.get_all_users().await;
                let json = serde_json::to_vec(&all_users).unwrap();
                let json_str = str::from_utf8(json.as_slice()).unwrap();

                response = Response::new(
                    self.create_message(format!("{{\"users\":\"{}\"}}", json_str))
                );
            },
            StatusCode::UNAUTHORIZED => {
                response = Response::new(
                    self.create_message("{\"message\":\"Insufficient access or token is invalid or missing\"}")
                );
            },
            StatusCode::FORBIDDEN => {
                response = Response::new(
                    self.create_message("{\"message\":\"Tampering with the JWT is forbidden\"}")
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
    
    pub async fn get_user(&mut self, req: Request<hyper::body::Incoming>) -> ServerResult {
        let uid = req.uri().path().split('/').collect::<Vec<&str>>()[2].parse::<i32>().unwrap();

        let mut response = Response::new(self.create_message(""));
        let status = response.status_mut();
        *status = StatusCode::OK;

        let token = self.get_token_from_request(&req);
        
        match token {
            Some(token) => {
                let claims = match jwt::decode_jwt(token.as_ref()) {
                    Ok(claims) => Some(claims),
                    Err(_) => {
                        *status = StatusCode::FORBIDDEN;
                        None
                    },
                };
                
                match claims {
                    Some(claims) => {
                        let is_expired = self.redis.is_token_expired(claims.uid).await; 
                        println!("Current token, (expired: {}): {:?}", is_expired, claims);
                        if is_expired || (claims.uid != uid && !claims.admin) {
                            *status = StatusCode::UNAUTHORIZED
                        }
                    },
                    None => *status = StatusCode::INTERNAL_SERVER_ERROR,
                }
            }
            None => *status = StatusCode::UNAUTHORIZED,
        }

        let user = match self.postgres.get_user(uid).await {
            Some(user) => Some(user),
            None => {
                *status = StatusCode::NOT_FOUND;
                None
            },
        };

        match *status {
            StatusCode::OK => {
                let json = serde_json::to_string(&user).unwrap();

                response = Response::new(
                    self.create_message(format!("{{\"users\":\"{}\"}}", json))
                );
            },
            StatusCode::UNAUTHORIZED => {
                response = Response::new(
                    self.create_message("{\"message\":\"Insufficient access or token is invalid or missing\"}")
                );
            },
            StatusCode::FORBIDDEN => {
                response = Response::new(
                    self.create_message("{\"message\":\"Tampering with the JWT is forbidden\"}")
                );
            },
            StatusCode::NOT_FOUND => {
                response = Response::new(
                    self.create_message("{\"message\":\"Could not find user with UID\"}")
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
    
    pub async fn update_user(&mut self, req: Request<hyper::body::Incoming>) -> ServerResult {
        let uid = req.uri().path().split('/').collect::<Vec<&str>>()[2].parse::<i32>().unwrap();

        let mut response = Response::new(self.create_message(""));
        let status = response.status_mut();
        *status = StatusCode::OK;

        let token = self.get_token_from_request(&req);
        
        match token {
            Some(token) => {
                let claims = match jwt::decode_jwt(token.as_ref()) {
                    Ok(claims) => Some(claims),
                    Err(_) => {
                        *status = StatusCode::FORBIDDEN;
                        None
                    },
                };
                
                match claims {
                    Some(claims) => {
                        let is_expired = self.redis.is_token_expired(claims.uid).await; 
                        println!("Current token, (expired: {}): {:?}", is_expired, claims);
                        if is_expired || (claims.uid != uid && !claims.admin) {
                            *status = StatusCode::UNAUTHORIZED
                        }
                    },
                    None => *status = StatusCode::INTERNAL_SERVER_ERROR,
                }
            }
            None => *status = StatusCode::UNAUTHORIZED,
        }

        let body = req.collect().await?.to_bytes();
        let body_json: Option<serde_json::Value> = match serde_json::from_slice(body.as_ref()) {
            Ok(json) => json,
            Err(_) => None,
        };
    
        let mut postgres_user = User::new();
        match body_json {
            Some(user) => 'validate_body: {
                if *status == StatusCode::UNAUTHORIZED {
                    break 'validate_body;
                }

                let required_fields = ["username", "firstName", "lastName"];
                for field in required_fields {
                    if user[field].is_null() {
                        *status = StatusCode::BAD_REQUEST;
                        break 'validate_body;
                    }
                }

                postgres_user.username = String::from(user["username"].as_str().unwrap());
                postgres_user.first_name = String::from(user["firstName"].as_str().unwrap());
                postgres_user.last_name = String::from(user["lastName"].as_str().unwrap());

                let update_result = self.postgres.update_user(uid, &postgres_user).await;
                match update_result {
                    Ok(rows_changed) => println!("Rows updated ({})", rows_changed),
                    Err(err) => {
                        eprintln!("User was not updated in the database ({})", err.as_db_error().unwrap().message());
                        *status = StatusCode::INTERNAL_SERVER_ERROR;
                    },
                }
            },
            None => *status = StatusCode::BAD_REQUEST,
        }

        match *status {
            StatusCode::OK => {
                response = Response::new(
                    self.create_message(format!("{{\"message\":\"Updated user with ID {}\"}}", uid))
                );
            },
            StatusCode::UNAUTHORIZED => {
                response = Response::new(
                    self.create_message("{\"message\":\"Insufficient access or token is invalid or missing\"}")
                );
            },
            StatusCode::FORBIDDEN => {
                response = Response::new(
                    self.create_message("{\"message\":\"Tampering with the JWT is forbidden\"}")
                );
            },
            StatusCode::NOT_FOUND => {
                response = Response::new(
                    self.create_message("{\"message\":\"Could not find user with UID\"}")
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
    
    pub async fn delete_user(&mut self, req: Request<hyper::body::Incoming>) -> ServerResult {
        let uid = req.uri().path().split('/').collect::<Vec<&str>>()[2].parse::<i32>().unwrap();

        let mut response = Response::new(self.create_message(""));
        let status = response.status_mut();
        *status = StatusCode::OK;

        let token = self.get_token_from_request(&req);
        
        match token {
            Some(token) => {
                let claims = match jwt::decode_jwt(token.as_ref()) {
                    Ok(claims) => Some(claims),
                    Err(_) => {
                        *status = StatusCode::FORBIDDEN;
                        None
                    },
                };
                
                match claims {
                    Some(claims) => {
                        let is_expired = self.redis.is_token_expired(claims.uid).await; 
                        println!("Current token, (expired: {}): {:?}", is_expired, claims);
                        if is_expired || (claims.uid != uid && !claims.admin) {
                            *status = StatusCode::UNAUTHORIZED
                        }
                    },
                    None => *status = StatusCode::INTERNAL_SERVER_ERROR,
                }
            },
            None => *status = StatusCode::UNAUTHORIZED,
        }

        if *status == StatusCode::OK {
            let user = self.postgres.get_user(uid).await;
            if user.is_some() {
                let delete_result = self.postgres.delete_user(uid).await;
                match delete_result {
                    Ok(rows_deleted) => println!("Rows deleted ({})", rows_deleted),
                    Err(err) => {
                        eprintln!("User was not deleted ({})", err.as_db_error().unwrap().message());
                        *status = StatusCode::INTERNAL_SERVER_ERROR;
                    },
                };

                self.redis.remove_token(uid).await.unwrap();
            } else {
                *status = StatusCode::NOT_FOUND;
            }
        }

        match *status {
            StatusCode::OK => {
                response = Response::new(
                    self.create_message(format!("{{\"message\":\"Deleted user with ID {}\"}}", uid))
                );
            },
            StatusCode::UNAUTHORIZED => {
                response = Response::new(
                    self.create_message("{\"message\":\"Insufficient access or token is invalid or missing\"}")
                );
            },
            StatusCode::FORBIDDEN => {
                response = Response::new(
                    self.create_message("{\"message\":\"Tampering with the JWT is forbidden\"}")
                );
            },
            StatusCode::NOT_FOUND => {
                response = Response::new(
                    self.create_message("{\"message\":\"Could not find user with UID\"}")
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
    
    fn get_token_from_request(&self, req: &Request<hyper::body::Incoming>) -> Option<String> {
        match req.headers().get("Authorization") {
            Some(bearer) => {
                let (_, token) = bearer.to_str().unwrap().split_once(' ').unwrap();
                Some(String::from(token))
            },
            None => None,
        }
    }
}

fn hash_password(password: &[u8]) -> String {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    argon2.hash_password(password, &salt).unwrap().to_string()
}

fn verify_password(password: &[u8], hash: &[u8]) -> bool {
    let password_hash = PasswordHash::new(str::from_utf8(hash).ok().unwrap()).unwrap();
    let argon2 = Argon2::default();
    argon2.verify_password(password, &password_hash).is_ok()
}
