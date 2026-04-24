import birl
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import logging
import order.{type Order, Order}
import order_item.{Item}
import pg_value
import pgl.{type Connection, type PglError}

pub opaque type PostgresClient {
  PostgresClient(client: Connection)
}

pub fn new() -> PostgresClient {
  logging.log(
    logging.Info,
    "Connecting to Postgres on postgres://foodguy:foodServiceDB@postgresdb:5432/foodguy",
  )

  let config =
    pgl.config
    |> pgl.host("postgresdb")
    |> pgl.port(5432)
    |> pgl.database("foodguy")
    |> pgl.username("foodguy")
    |> pgl.password("foodServiceDB")
    |> pgl.ssl(pgl.SslDisabled)

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
    order_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY NOT NULL,
    user_id INT REFERENCES users(uid) NOT NULL,
    order_date DATE NOT NULL,
    status VARCHAR(10) NOT NULL
  )"
  |> pgl.execute(connection)
}

fn create_order_items_table(connection: Connection) -> Result(Int, PglError) {
  "CREATE TABLE IF NOT EXISTS order_items(
    order_id INT REFERENCES orders(order_id) NOT NULL,
    item TEXT NOT NULL,
    price REAL NOT NULL
  )"
  |> pgl.execute(connection)
}

pub fn create_order(
  client: PostgresClient,
  user_id: Int,
) -> Result(Nil, PglError) {
  // It gets sliced because the format is 2026-04-22Z
  // Should be 2026-04-22
  let date =
    birl.now()
    |> birl.to_date_string()
    |> string.slice(0, 10)

  let sql =
    "INSERT INTO orders(user_id, order_date, status) VALUES("
    <> int.to_string(user_id)
    <> ", '"
    <> date
    <> "', 'created')"
  logging.log(logging.Debug, sql)

  sql
  |> pgl.execute(client.client)
  |> result.map(fn(_) { Nil })
}

pub fn get_orders(client: PostgresClient, user_id: Int) -> List(Order) {
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

  let assert Ok(orders) =
    result.map(query, fn(q) {
      logging.log(
        logging.Debug,
        "Found " <> int.to_string(list.length(q.rows)) <> " rows",
      )
      q.rows
      |> list.try_fold(dict.new(), fn(om: Dict(Int, Order), dynamic) {
        let assert Ok(order) =
          decode.run(dynamic, {
            use order_id <- decode.field(0, decode.int)
            use order_date_dynamic <- decode.field(1, decode.dynamic)
            let assert Ok(order_date) =
              decode.run(order_date_dynamic, {
                use year <- decode.field(0, decode.int)
                use month <- decode.field(1, decode.int)
                use day <- decode.field(2, decode.int)
                decode.success(string.join(
                  [
                    int.to_string(year),
                    int.to_string(month),
                    int.to_string(day),
                  ],
                  "-",
                ))
              })
            use status <- decode.field(2, decode.string)
            use item_name <- decode.field(3, decode.string)
            use item_price <- decode.field(4, decode.float)
            decode.success(
              Order(order_id, user_id, order_date, status, [
                Item(item_name, item_price),
              ]),
            )
          })

        let assert Ok(item) = list.first(order.items)
        let new_dict = case dict.get(om, order.id) {
          Ok(o) -> {
            let new_items = list.append(o.items, [item])
            let new_order =
              Order(order.id, user_id, order.date, order.status, new_items)
            dict.insert(om, order.id, new_order)
          }
          Error(_) -> {
            let order =
              Order(order.id, user_id, order.date, order.status, [
                item,
              ])
            dict.insert(om, order.id, order)
          }
        }

        Ok(new_dict)
      })
    })

  orders
  |> result.unwrap(dict.new())
  |> dict.values()
}

pub fn get_order(
  client: PostgresClient,
  user_id: Int,
  order_id: Int,
) -> Result(Option(Order), Nil) {
  let query =
    "
  SELECT o.order_id, o.order_date, o.status, oi.item, oi.price
  FROM orders o
  LEFT JOIN order_items oi
  ON o.order_id = oi.order_id
  WHERE o.user_id = $1
  AND o.order_id = $2
  "
    |> pgl.sql()
    |> pgl.values([pg_value.int(user_id), pg_value.int(order_id)])
    |> pgl.query(client.client)

  let assert Ok(orders) =
    result.map(query, fn(q) {
      logging.log(
        logging.Debug,
        "Found " <> int.to_string(list.length(q.rows)) <> " rows",
      )
      q.rows
      |> list.try_fold(dict.new(), fn(om: Dict(Int, Order), dynamic) {
        let assert Ok(order) =
          decode.run(dynamic, {
            use order_id <- decode.field(0, decode.int)
            use order_date_dynamic <- decode.field(1, decode.dynamic)
            let assert Ok(order_date) =
              decode.run(order_date_dynamic, {
                use year <- decode.field(0, decode.int)
                use month <- decode.field(1, decode.int)
                use day <- decode.field(2, decode.int)
                decode.success(string.join(
                  [
                    int.to_string(year),
                    int.to_string(month),
                    int.to_string(day),
                  ],
                  "-",
                ))
              })
            use status <- decode.field(2, decode.string)
            use item_name <- decode.field(3, decode.string)
            use item_price <- decode.field(4, decode.float)
            decode.success(
              Order(order_id, user_id, order_date, status, [
                Item(item_name, item_price),
              ]),
            )
          })

        let assert Ok(item) = list.first(order.items)
        let new_dict = case dict.get(om, order.id) {
          Ok(o) -> {
            let new_items = list.append(o.items, [item])
            let new_order =
              Order(order.id, user_id, order.date, order.status, new_items)
            dict.insert(om, order.id, new_order)
          }
          Error(_) -> {
            let order =
              Order(order.id, user_id, order.date, order.status, [
                item,
              ])
            dict.insert(om, order.id, order)
          }
        }

        Ok(new_dict)
      })
    })

  let final_order =
    orders
    |> result.unwrap(dict.new())
    |> dict.values()
    |> list.first()

  case final_order {
    Ok(o) -> Ok(Some(o))
    Error(_) -> Ok(None)
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
  SET status = '" <> status <> "'
  WHERE user_id = " <> int.to_string(user_id) <> " AND order_id = " <> int.to_string(
      order_id,
    )

  order_sql
  |> pgl.execute(client.client)
  |> result.map(fn(_) { Nil })
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
  WHERE user_id = " <> int.to_string(user_id) <> " AND order_id = " <> int.to_string(
      order_id,
    )

  order_sql
  |> pgl.execute(client.client)
  |> result.map(fn(_) { Nil })
}
