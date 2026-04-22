import gleam/bytes_tree
import gleam/erlang/process
import gleam/http.{Delete, Get, Post, Put}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json.{type Json}
import gleam/string
import logging
import mist.{type Connection, type ResponseData}
import order
import postgres

pub fn main() -> Nil {
  logging.configure()
  logging.set_level(logging.Debug)

  let sql_client = postgres.new()

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
        Get, ["orders"] -> {
          let orders =
            postgres.get_orders(sql_client, 0)
            |> json.array(order.to_json)
          json.object([#("orders", orders)])
          |> create_response(200)
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

fn create_message(message: String) -> Json {
  json.object([#("message", json.string(message))])
}

fn create_response(response: Json, code: Int) -> Response(ResponseData) {
  let json_str = json.to_string(response)
  response.new(code)
  |> response.prepend_header("Content-Type", "application/json")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(json_str)))
}
