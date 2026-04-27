import gleam/bytes_tree
import gleam/dynamic/decode.{type Decoder}
import gleam/erlang/process
import gleam/http.{Delete, Get, Post, Put}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import jwt.{type JwtClaims}
import logging
import mist.{type Connection, type ResponseData}
import order.{type Order}
import postgres.{type PostgresClient}
import rabbit

pub fn main() -> Nil {
  logging.configure()
  logging.set_level(logging.Debug)

  let sql_client = postgres.new()
  let assert Ok(_) = rabbit.start()

  // This comes from the mist documentation
  // https://hexdocs.pm/mist/index.html
  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case mist.get_connection_info(req.body) {
        Ok(info) -> {
          logging.log(logging.Info, mist.connection_info_to_string(info))
        }
        Error(_) -> {
          logging.log(logging.Info, "An error occured")
        }
      }

      case req.method, request.path_segments(req) {
        Get, [] | Get, ["healthcheck"] -> {
          create_message("Service is healthy")
          |> create_response(200)
        }
        Post, ["order"] -> {
          case create_order(req, sql_client) {
            Ok(_) -> {
              create_message("Order added")
              |> create_response(200)
            }
            Error(err) -> err
          }
        }
        Get, ["orders"] -> {
          case get_orders(req, sql_client) {
            Ok(orders) -> {
              json.object([#("order", json.array(orders, order.to_json))])
              |> create_response(200)
            }
            Error(message) -> message
          }
        }
        Get, ["order", order_id] -> {
          case get_order(req, sql_client, order_id) {
            Ok(order) -> {
              case order {
                Some(o) -> {
                  json.object([#("order", order.to_json(o))])
                  |> create_response(200)
                }
                None -> {
                  json.object([#("order", json.null())])
                  |> create_response(200)
                }
              }
            }
            Error(message) -> message
          }
        }
        Put, ["order", order_id] -> {
          case update_order(req, sql_client, order_id) {
            Ok(_) -> {
              create_message("Updated order with order_id " <> order_id)
              |> create_response(200)
            }
            Error(message) -> message
          }
        }
        Delete, ["order", order_id] -> {
          case delete_order(req, sql_client, order_id) {
            Ok(_) -> {
              create_message("Deleted order with order_id " <> order_id)
              |> create_response(200)
            }
            Error(message) -> message
          }
        }
        method, path -> {
          let message =
            "Invalid endpoint ("
            <> http.method_to_string(method)
            <> " "
            <> string.join(path, "/")
            <> ")"
          create_message(message)
          |> create_response(404)
        }
      }
    }
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(9133)
    |> mist.start

  process.sleep_forever()
}

fn create_order(
  req: Request(Connection),
  postgres_client: PostgresClient,
) -> Result(Nil, Response(ResponseData)) {
  use token <- result.try(get_jwt_from_header(req.headers))
  try_or_message(
    postgres.create_order(postgres_client, token.uid),
    "An error occurred",
    500,
    fn(_) { Ok(Nil) },
  )
}

fn get_orders(
  req: Request(Connection),
  postgres_client: PostgresClient,
) -> Result(List(Order), Response(ResponseData)) {
  use token <- result.try(get_jwt_from_header(req.headers))
  Ok(postgres.get_orders(postgres_client, token.uid))
}

fn get_order(
  req: Request(Connection),
  postgres_client: PostgresClient,
  order_id_str: String,
) -> Result(Option(Order), Response(ResponseData)) {
  use token <- result.try(get_jwt_from_header(req.headers))
  use order_id <- result.try(parse_path(order_id_str))
  case token.uid == order_id || token.admin {
    True -> {
      try_or_message(
        postgres.get_order(postgres_client, token.uid, order_id),
        "An error occurred",
        500,
        fn(order) { Ok(order) },
      )
    }
    False -> {
      create_message("Not allowed to view that order")
      |> create_response(401)
      |> Error()
    }
  }
}

fn update_order(
  req: Request(Connection),
  postgres_client: PostgresClient,
  order_id_str: String,
) -> Result(Nil, Response(ResponseData)) {
  let decoder = {
    use status <- decode.field("status", decode.string)
    decode.success(#("status", status))
  }

  use body_result <- result.try(parse_body(req, decoder))

  use token <- result.try(get_jwt_from_header(req.headers))
  use order_id <- result.try(parse_path(order_id_str))
  case token.uid == order_id || token.admin {
    True -> {
      try_or_message(
        postgres.update_order(
          postgres_client,
          token.uid,
          order_id,
          string.lowercase(body_result.1),
        ),
        "An error occurred",
        500,
        fn(_) { Ok(Nil) },
      )
    }
    False -> {
      create_message("Not allowed to update that order")
      |> create_response(401)
      |> Error()
    }
  }
}

fn delete_order(
  req: Request(Connection),
  postgres_client: PostgresClient,
  order_id_str: String,
) -> Result(Nil, Response(ResponseData)) {
  use token <- result.try(get_jwt_from_header(req.headers))
  use order_id <- result.try(parse_path(order_id_str))
  case token.uid == order_id || token.admin {
    True -> {
      try_or_message(
        postgres.delete_order(postgres_client, token.uid, order_id),
        "An error occurred",
        500,
        fn(_) { Ok(Nil) },
      )
    }
    False -> {
      create_message("Not allowed to delete that order")
      |> create_response(401)
      |> Error()
    }
  }
}

fn create_message(message: String) -> Json {
  json.object([#("message", json.string(message))])
}

fn create_response(json: Json, code: Int) -> Response(ResponseData) {
  let json_str = json.to_string(json)

  response.new(code)
  |> response.prepend_header("Content-Type", "application/json")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(json_str)))
}

fn try_or_message(
  result_value: Result(a, e),
  message: String,
  code: Int,
  callback: fn(a) -> Result(b, Response(ResponseData)),
) -> Result(b, Response(ResponseData)) {
  case result_value {
    Ok(x) -> callback(x)
    Error(_) -> Error(create_message(message) |> create_response(code))
  }
}

fn get_jwt_from_header(
  headers: List(#(String, String)),
) -> Result(JwtClaims, Response(ResponseData)) {
  let header_result =
    list.find(headers, fn(header) { header.0 == "authorization" })

  use auth <- try_or_message(
    header_result,
    "Could not find Authorization header",
    401,
  )
  use split <- try_or_message(
    string.split_once(auth.1, " "),
    "Header is incorrectly shaped",
    401,
  )

  use claims <- try_or_message(
    jwt.decode_jwt(split.1),
    "Could not decode JWT token. It is forbidden to tamper with tokens",
    403,
  )
  Ok(claims)
}

fn parse_path(segment: String) -> Result(Int, Response(ResponseData)) {
  use number <- try_or_message(
    int.parse(segment),
    "Path segment must be number",
    400,
  )
  Ok(number)
}

fn parse_body(
  req: Request(Connection),
  decoder: Decoder(#(String, String)),
) -> Result(#(String, String), Response(ResponseData)) {
  let results =
    mist.read_body(req, 1024 * 1024 * 10)
    |> result.map(fn(req) {
      result.map_error(json.parse_bits(req.body, decoder), fn(_) {
        create_message("Could not parse request body") |> create_response(400)
      })
    })
    |> result.map_error(fn(_) {
      create_message("Could not read request body") |> create_response(500)
    })

  use body_read <- result.try(results)
  use body_parse <- result.try(body_read)
  Ok(body_parse)
}
