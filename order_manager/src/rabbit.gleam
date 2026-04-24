import carotte.{type Client}
import logging

pub opaque type RabbitMq {
  RabbitMq(client: Client)
}

pub fn new() -> RabbitMq {
  logging.log(logging.Info, "Connecting to Rabbit")
  let assert Ok(client) =
    carotte.ClientConfig(
      ..carotte.default_client(),
      host: "rabbitmq",
      port: 5672,
    )
    |> carotte.start()

  let assert Ok(channel) = carotte.open_channel(client)

  let assert Ok(_) =
    carotte.QueueConfig(..carotte.default_queue("order_list"), durable: True)
    |> carotte.declare_queue(channel)

  let assert Ok(_) =
    carotte.bind_queue(
      channel: channel,
      queue: "order_list",
      exchange: "amq.topic",
      routing_key: "my_routing_key",
    )

  logging.log(logging.Info, "Connected to Rabbit")
  RabbitMq(client)
}
