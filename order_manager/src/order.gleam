import gleam/json.{type Json}
import order_item.{type Item}

pub type Order {
  Order(id: Int, date: String, status: String, items: List(Item))
}

pub fn to_json(order: Order) -> Json {
  json.object([
    #("order_id", json.int(order.id)),
    #("order_date", json.string(order.date)),
    #("status", json.string(order.status)),
    #("items", json.array(order.items, order_item.to_json)),
  ])
}
