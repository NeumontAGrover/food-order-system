use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Header, Validation, decode, encode, errors::Error};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct JwtClaims {
    pub uid: i32,
    pub admin: bool,
    exp: u64,
    iat: u64,
}

const SECRET: &str = "0c090b0f1d270a41670da50c444163066932e7b52d23c5cecb0e34e67c949aef";

pub fn create_jwt(uid: i32, admin: bool, current_time: u64) -> Result<String, Error> {
    let one_week_sec = 604800;
    let claims = JwtClaims { uid, admin, exp: current_time + one_week_sec, iat: current_time };
    let token = encode(&Header::default(), &claims, &EncodingKey::from_secret(SECRET.as_ref()))?;
    Ok(token)
}

pub fn decode_jwt(jwt: &str) -> Result<JwtClaims, Error> {
    let token = decode::<JwtClaims>(
        &jwt,
        &DecodingKey::from_secret(SECRET.as_ref()),
        &Validation::new(Algorithm::HS256)
    )?;
    Ok(token.claims)
}
