import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/list
import gleam/result
import logging
import order.{type Order, Order}
import order_item.{Item}
import pg_value
import pgl.{type Connection, type PglError}

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
    Ok(_) -> {
      logging.log(logging.Info, "Created order and order_items table")
    }
    Error(err) -> {
      logging.log(logging.Error, pgl.error_to_string(err))
    }
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
  )"
  |> pgl.execute(connection)
}

fn create_order_items_table(connection: Connection) -> Result(Int, PglError) {
  "CREATE TABLE IF NOT EXISTS order_items(
    order_id INT FOREIGN KEY REFERENCES orders(order_id) NOT NULL,
    item TEXT NOT NULL,
    price MONEY NOT NULL
  )"
  |> pgl.execute(connection)
}

pub fn get_orders(client: PostgresClient, user_id: Int) -> List(Order) {
  let orders_map: Dict(Int, Order) = dict.new()

  let query =
    "
  SELECT o.order_id, o.order_date, o.status, oi.item, oi.price
  FROM orders o
  LEFT JOIN order_items oi
  ON o.order_id = oi.order_id
  WHERE o.user_id = $1
  "
    |> pgl.sql()
    |> pgl.values([pg_value.int(user_id)])
    |> pgl.query(client.client)

  let assert Ok(_) =
    result.map(query, fn(q) {
      q.rows
      |> list.try_each(
        decode.run(_, {
          use order_id <- decode.field(0, decode.int)
          use order_date <- decode.field(1, decode.string)
          use status <- decode.field(2, decode.string)
          use item_name <- decode.field(3, decode.string)
          use item_price <- decode.field(4, decode.float)

          let _ = case dict.get(orders_map, order_id) {
            Ok(o) -> {
              let _ = list.append(o.items, [Item(item_name, item_price)])
              Nil
            }
            Error(_) -> {
              let order = Order(order_id, order_date, status, [])
              let _ = dict.insert(orders_map, order_id, order)
              Nil
            }
          }

          decode.success(Nil)
        }),
      )
    })

  dict.values(orders_map)
}
