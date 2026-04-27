import gleam/json.{type Json}

pub type Item {
  Item(uid: Int, name: String, price: Float, quantity: Int)
}

pub fn to_json(item: Item) -> Json {
  json.object([
    #("uid", json.int(item.uid)),
    #("item", json.string(item.name)),
    #("price", json.float(item.price)),
    #("quantity", json.int(item.quantity)),
  ])
}
