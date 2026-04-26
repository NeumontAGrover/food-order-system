require "http/server"
require "./duck_db"
require "./server_handler"

include DuckClient
include ServerHandler

duckdb = DuckDb.new

PORT = 45854
server = HTTP::Server.new do |con|
  con.response.content_type = "application/json"

  case con.request.path
  when "/healthcheck"
    healthcheck con
  when "/order"
    item 0, con, duckdb
  when "/order-list"
    list con, duckdb
  when "/submit-items"
    submit con, duckdb
  else
    if con.request.path.includes? "/order"
      split_path = con.request.path.split '/'
      order_uid = split_path[2].to_i
      item order_uid, con, duckdb
    else
      con.response.status_code = 400
      con.response.print "{\"message\":\"No available endpoint\"}"
    end
  end
end

server.bind_tcp "0.0.0.0", 45854
server.listen
