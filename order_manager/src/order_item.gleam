import gleam/json.{type Json}

pub type Item {
  Item(name: String, price: Float)
}

pub fn to_json(item: Item) -> Json {
  json.object([
    #("item", json.string(item.name)),
    #("price", json.float(item.price)),
  ])
}
