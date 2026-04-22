import gleam/dynamic/decode
import gleam/result
import gwt

const secret = "0c090b0f1d270a41670da50c444163066932e7b52d23c5cecb0e34e67c949aef"

pub type JwtClaims {
  JwtClaims(uid: Int, admin: Bool, exp: Int, iat: Int)
}

pub fn decode_jwt(jwt_string: String) -> Result(JwtClaims, gwt.JwtDecodeError) {
  use jwt <- result.try(gwt.from_signed_string(jwt_string, secret))
  use uid <- result.try(gwt.get_payload_claim(jwt, "uid", decode.int))
  use admin <- result.try(gwt.get_payload_claim(jwt, "admin", decode.bool))
  use exp <- result.try(gwt.get_payload_claim(jwt, "exp", decode.int))
  use iat <- result.try(gwt.get_payload_claim(jwt, "iat", decode.int))
  Ok(JwtClaims(uid, admin, exp, iat))
}
