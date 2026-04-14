require "http/server"
require "json"
require "./duck_db"

module ServerHandler
  alias Context = HTTP::Server::Context

  def healthcheck(con : Context)
    if (con.request.method != "GET")
      con.response.status_code = 405
      con.response.print "{\"message\":\"Healthcheck must use GET\"}"
      return
    end

    con.response.status_code = 200
    con.response.print "{\"message\":\"Order List is healthy\"}"
  end

  def item(con : Context, db : DuckDb)
    case con.request.method
    when "POST"
      body = con.request.body
      if body.nil?
        con.response.status_code = 400
        con.response.print "{\"message\":\"A body must be provided\"}"
        return
      end
      
      item = FoodItem.from_json(body.not_nil!)
      if !item.has_key?("foodName") || !item.has_key?("price") || !item.has_key?("quantity")
        con.response.status_code = 400
        con.response.print "{\"message\":\"The body must contain 'foodName', 'price', and 'quantity'\"}"
        return
      end
      
      begin
        db.add_item 0_u64, item
        con.response.status_code = 201
        con.response.print "{\"message\":\"Item added\"}"
      rescue exception
        con.response.status_code = 500
        con.response.print "{\"message\":\"An error occurred\"}"
        puts exception.message
      end
    when "PATCH"
      body = con.request.body
      body_string = body.not_nil!.gets_to_end
      if body_string.size <= 0
        con.response.status_code = 400
        con.response.print "{\"message\":\"A body must be provided\"}"
        return
      end

      quantity_json = JSON.parse(body_string)

      begin
        food_name = quantity_json["foodName"].as_s?
        if food_name.nil?; raise "foodName is nil"; end
          
        quantity = quantity_json["quantity"].as_i?
        if quantity.nil?; raise "foodName is nil"; end

        db.update_quantity 0_u64, food_name, quantity.to_u32
        con.response.status_code = 200
        con.response.print "{\"message\":\"#{food_name} quantity updated to #{quantity}\"}"
      rescue exception
        con.response.status_code = 500
        con.response.print "{\"message\":\"An error occurred (#{exception.message})\"}"
      end
    when "DELETE"
      body = con.request.body
      body_string = body.not_nil!.gets_to_end
      if body_string.size <= 0
        con.response.status_code = 400
        con.response.print "{\"message\":\"A body must be provided\"}"
        return
      end

      quantity_json = JSON.parse(body_string)

      begin
        food_name = quantity_json["foodName"].as_s?
        if food_name.nil?; raise "foodName is nil"; end

        db.remove_item 0_u64, food_name
        con.response.status_code = 200
        con.response.print "{\"message\":\"#{food_name} removed\"}"
      rescue exception
        con.response.status_code = 500
        con.response.print "{\"message\":\"An error occurred (#{exception.message})\"}"
      end
    else
      con.response.status_code = 405
      con.response.print "{\"message\":\"Method is not allowed\"}"
    end
  end

  def list(con : Context, db : DuckDb)
    case con.request.method
    when "GET"
      begin
        order_list = db.get_order_list(0).to_json

        con.response.status_code = 200
        con.response.print order_list
      rescue
        con.response.status_code = 500
        con.response.print "{\"message\":\"An error occured\"}"
      end
    when "DELETE"
      begin
        order_list = db.clear_list 0

        con.response.status_code = 200
        con.response.print "{\"message\":\"Cleared order list\"}"
      rescue
        con.response.status_code = 500
        con.response.print "{\"message\":\"An error occured\"}"
      end
    else
      con.response.status_code = 405
      con.response.print "{\"message\":\"Method is not allowed\"}"
    end
  end
end