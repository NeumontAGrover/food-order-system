require "jwt"

SECRET_KEY = "0c090b0f1d270a41670da50c444163066932e7b52d23c5cecb0e34e67c949aef"

module Jwt
  def decode_token(token : String)
    payload, _ = JWT.decode(token, SECRET_KEY, JWT::Algorithm::HS256)
    return payload
  end
end
