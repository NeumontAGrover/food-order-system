import gleam/result
import pgl.{type Connection, type PglError}
import logging

pub opaque type PostgresClient {
  PostgresClient(client: Connection)
}

pub fn new() -> PostgresClient {
  let config =
    pgl.config
    |> pgl.host("postgres")
    |> pgl.port(5432)
    |> pgl.database("foodguy")
    |> pgl.username("foodguy")
    |> pgl.password("foodServiceDB")

  let db = pgl.new(config)
  let assert Ok(_) = pgl.start(db)
  let connection = pgl.connection(db)
  case setup_db(connection) {
    Ok(_) -> { logging.log(logging.Info, "Created order and order_items table") }
    Error(err) -> { logging.log(logging.Error, pgl.error_to_string(err)) }
  }

  PostgresClient(connection)
}

fn setup_db(connection: Connection) -> Result(Nil, PglError) {
  use _ <- result.try(create_order_table(connection))
  use _ <- result.try(create_order_items_table(connection))
  Ok(Nil)
}

fn create_order_table(connection: Connection) -> Result(Int, PglError) {
  "CREATE TABLE IF NOT EXISTS orders(
    order_id INT GENERATED PRIMARY KEY NOT NULL,
    user_id INT FOREIGN KEY REFERECES users(uid) NOT NULL,
    order_date DATE NOT NULL,
    status VARCHAR(10) NOT NULL
  )" |> pgl.execute(connection)
}

fn create_order_items_table(connection: Connection) -> Result(Int, PglError) {
  "CREATE TABLE IF NOT EXISTS order_items(
    order_id INT FOREIGN KEY REFERENCES orders(order_id) NOT NULL,
    item TEXT NOT NULL,
    price MONEY NOT NULL
  )" |> pgl.execute(connection)
}

pub fn get_orders(client: PostgresClient) {
  ""
}
