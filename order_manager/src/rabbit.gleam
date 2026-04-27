import carotte.{type ConsumeError, type Deliver, type Payload}
import gleam/bit_array
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import logging
import order_item.{Item}
import postgres

pub fn start() -> Result(Nil, ConsumeError) {
  logging.log(logging.Info, "Connecting to Rabbit")
  let assert Ok(client) =
    carotte.ClientConfig(
      ..carotte.default_client(),
      host: "rabbitmq",
      port: 5672,
    )
    |> carotte.start()

  let assert Ok(channel) = carotte.open_channel(client)

  let assert Ok(consumer) =
    process.new_name("rabbit") |> carotte.start_consumer()

  use _ <- result.try(carotte.subscribe(
    consumer,
    channel,
    "order_list",
    order_list_callback,
  ))

  logging.log(logging.Info, "Connected to Rabbit")

  Ok(Nil)
}

fn order_list_callback(message: Payload, _delivery: Deliver) -> Nil {
  logging.log(logging.Info, "Consumed a message from the order_list MQ")

  let decoder = {
    use uid <- decode.field("uid", decode.int)
    use food_name <- decode.field("foodName", decode.string)
    use price <- decode.field("price", decode.float)
    use quantity <- decode.field("quantity", decode.int)
    decode.success(Item(uid, food_name, price, quantity))
  }

  let decode_list = decode.list(decoder)

  let assert Ok(message_str) = bit_array.to_string(message.payload)
  let assert Ok(items) = json.parse(message_str, decode_list)

  let client = postgres.new()

  let assert Ok(user_id) = list.first(items)
  let assert Ok(order_id) = postgres.create_order(client, user_id.uid)
  logging.log(
    logging.Info,
    "Creating a new order (" <> int.to_string(order_id) <> ") for new items",
  )

  let _ = postgres.add_items(client, order_id, items)
  Nil
}
