use jsonwebtoken::{Algorithm, DecodingKey, EncodingKey, Header, Validation, decode, encode, errors::Error};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct JwtClaims {
    pub uid: i32,
    pub admin: bool,
    exp: u128,
    iat: u128,
}

const SECRET: &str = "0c090b0f1d270a41670da50c444163066932e7b52d23c5cecb0e34e67c949aef";

pub fn create_jwt(uid: i32, admin: bool, current_time: u128) -> Result<String, Error> {
    let one_week_ms = 604_800_000;
    let claims = JwtClaims { uid, admin, exp: current_time + one_week_ms, iat: current_time };
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
