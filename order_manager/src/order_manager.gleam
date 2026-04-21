import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import logging
import mist.{type Connection, type ResponseData}

pub fn main() -> Nil {
  logging.configure()
  logging.set_level(logging.Debug)

  // This comes from the mist documentation
  // https://hexdocs.pm/mist/index.html
  let assert Ok(_) =
    fn (req: Request(Connection)) -> Response(ResponseData) {
      let _ = case mist.get_connection_info(req.body) {
        Ok(info) -> {
          logging.log(logging.Info, mist.connection_info_to_string(info))
        }
        Error(_) -> {
          logging.log(logging.Info, "An error occured")
        }
      }

      let success_message = json.object([#("message", json.string("Service is healthy"))])
        |> json.to_string
      
      response.new(200)
      |> response.prepend_header("Content-Type", "application/json")
      |> response.set_body(mist.Bytes(bytes_tree.from_string(success_message)))
    }
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(9133)
    |> mist.start

  process.sleep_forever()
}
