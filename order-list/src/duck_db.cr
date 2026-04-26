require "duckdb"

module DuckClient
  alias FoodItem = Hash(String, Int32 | Float32 | String)

  CONNECTION_STRING = "duckdb://./data/orders.db"

  class DuckDb
    def initialize
      begin
        DB.connect CONNECTION_STRING do |connection|
          connection.exec "CREATE TABLE IF NOT EXISTS order_list(
            uid INT NOT NULL,
            food_name TEXT NOT NULL,
            price FLOAT NOT NULL,
            quantity INT NOT NULL
          )"
        end

        puts "Connected to database"
      rescue ex
        puts "An error occured:\n#{ex.message}"
      end
    end

    def add_item(uid : Int32, item : FoodItem)
      DB.connect CONNECTION_STRING do |connection|
        connection.exec "INSERT INTO order_list VALUES(?, ?, ?, ?)", uid, item["foodName"], item["price"], item["quantity"]
      end
    end

    def get_order_list(uid : Int32) : Array(FoodItem)
      items = [] of FoodItem

      DB.connect CONNECTION_STRING do |connection|
        connection.query "SELECT food_name, price, quantity FROM order_list WHERE uid = ? ORDER BY food_name", uid do |result|
          result.each do
            name = result.read(String)
            price = result.read(Float32)
            quantity = result.read(Int32)
            items << {"uid" => uid, "foodName" => name, "price" => price, "quantity" => quantity}
          end
        end
      end

      return items
    end

    def update_quantity(uid : Int32, food_name : String, new_quantity : Int32)
      DB.connect CONNECTION_STRING do |connection|
        connection.exec "UPDATE order_list SET quantity = ? WHERE uid = ? AND food_name = ?", new_quantity, uid, food_name
      end
    end

    def remove_item(uid : Int32, food_name)
      DB.connect CONNECTION_STRING do |connection|
        connection.exec "DELETE FROM order_list WHERE uid = ? AND food_name = ?", uid, food_name
      end
    end

    def clear_list(uid : Int32)
      DB.connect CONNECTION_STRING do |connection|
        connection.exec "DELETE FROM order_list WHERE uid = ?", uid
      end
    end
  end
end
