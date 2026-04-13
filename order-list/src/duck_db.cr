require "duckdb"

module DuckClient
  alias FoodItem = {"foodName" : String, "price" : Float32, "quantity" : UInt32}

  CONNECTION_STRING = "duckdb://./data/orders.db"

  class DuckDb
    def initialize
      begin
        DB.connect CONNECTION_STRING do |connection|
          connection.exec "CREATE TABLE IF NOT EXISTS order_list(
            uid UBIGINT PRIMARY KEY NOT NULL,
            food_name TEXT NOT NULL,
            price FLOAT NOT NULL,
            quantity UINTEGER NOT NULL
          )"
        end

        puts "Connected to database"
      rescue ex
        puts "An error occured:\n#{ex.message}"
      end
    end

    def add_item(uid : UInt64, food_name : String, price : Float32, quantity : UInt32)
      DB.connect CONNECTION_STRING do |connection|
        connection.exec "INSERT INTO order_list VALUES(?, ?, ?, ?)", uid, food_name, price, quantity
      end
    end

    def get_order_list(uid : UInt64) : Array(FoodItem)
      items = [] of FoodItem

      DB.connect CONNECTION_STRING do |connection|
        connection.query "SELECT food_name, price, quantity FROM order_list ORDER BY food_name" do |result|
          result.each do
            name = result.read(String)
            price = result.read(Float32)
            quantity = result.read(UInt32)
            items << {"foodName" => name, "price" => price, "quantity" => quantity}
          end
        end
      end

      return items
    end

    def update_quantity(uid : UInt64, new_quantity : UInt32)
      DB.connect CONNECTION_STRING do |connection|
        connection.exec "UPDATE order_list SET quantity = ? WHERE uid = ?", new_quantity, uid
      end
    end
    
    def remove_item(uid : UInt64)
      DB.connect CONNECTION_STRING do |connection|
        connection.exec "DELETE FROM order_list WHERE uid = ?", uid
      end
    end
    
    def clear_list(uid : UInt64)
      DB.connect CONNECTION_STRING do |connection|
        connection.exec "DELETE FROM order_list"
      end
    end
  end
end