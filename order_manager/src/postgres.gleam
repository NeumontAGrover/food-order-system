import birl
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import logging
import order.{type Order, Order}
import order_item.{type Item, Item}
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

pub fn create_order(
  client: PostgresClient,
  user_id: Int,
) -> Result(Nil, PglError) {
  let date = birl.to_date_string(birl.now())

  let sql =
    "INSERT INTO orders VALUES("
    <> int.to_string(user_id)
    <> ", "
    <> date
    <> ", CREATED)"
  result.map(pgl.execute(sql, client.client), fn(_) { Nil })
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
              let order = Order(order_id, user_id, order_date, status, [])
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

pub fn get_order(
  client: PostgresClient,
  user_id: Int,
  order_id: Int,
) -> Result(Order, Nil) {
  let query =
    "
  SELECT order_id, order_date, status
  FROM orders
  WHERE o.user_id = $1, o.order_id = $2
  "
    |> pgl.sql()
    |> pgl.values([pg_value.int(user_id), pg_value.int(order_id)])
    |> pgl.query(client.client)

  let assert Ok(order_result) =
    result.map(query, fn(q) {
      q.rows
      |> list.try_map(
        decode.run(_, {
          use order_id <- decode.field(0, decode.int)
          use order_date <- decode.field(1, decode.string)
          use status <- decode.field(2, decode.string)

          decode.success(Order(order_id, user_id, order_date, status, []))
        }),
      )
    })

  case order_result {
    Ok(list) -> result.try(list.first(list), fn(first) { Ok(first) })
    Error(_) -> Error(Nil)
  }
}

pub fn update_order(
  client: PostgresClient,
  user_id: Int,
  order_id: Int,
  status: String,
) -> Result(Nil, PglError) {
  let order_sql = "
  UPDATE orders
  SET status = " <> status <> "
  WHERE user_id = " <> int.to_string(user_id) <> ", order_id = " <> int.to_string(
      order_id,
    )

  result.map(pgl.execute(order_sql, client.client), fn(_) { Nil })
}

pub fn delete_order(
  client: PostgresClient,
  user_id: Int,
  order_id: Int,
) -> Result(Nil, PglError) {
  let item_sql = "
  DELETE *
  FROM order_items
  WHERE order_id = " <> int.to_string(order_id)

  let _ = result.map(pgl.execute(item_sql, client.client), fn(_) { Nil })

  let order_sql = "
  DELETE *
  FROM orders
  WHERE user_id = " <> int.to_string(user_id) <> ", order_id = " <> int.to_string(
      order_id,
    )

  result.map(pgl.execute(order_sql, client.client), fn(_) { Nil })
}
