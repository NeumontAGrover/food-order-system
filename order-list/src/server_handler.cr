require "http/server"
require "json"
require "./duck_db"
require "./rabbit"
require "./jwt_module"

include RabbitClient
include Jwt

module ServerHandler
  alias Context = HTTP::Server::Context
  TEMP_UID = 0

  def healthcheck(con : Context)
    if (con.request.method != "GET")
      con.response.status_code = 405
      con.response.print "{\"message\":\"Healthcheck must use GET\"}"
      return
    end

    con.response.status_code = 200
    con.response.print "{\"message\":\"Order List is healthy\"}"
  end

  def item(uid : Int, con : Context, db : DuckDb)
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
        token = get_token_from_headers con.request.headers
        if token == Nil
          con.response.status_code = 401
          con.response.print "{\"message\":\"Missing or invalid JWT Token\"}"
          return
        end
        claims = decode_token token.as(String)

        db.add_item claims["uid"].as_i, item
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
        if food_name.nil?
          raise "foodName is nil"
        end

        quantity = quantity_json["quantity"].as_i?
        if quantity.nil?
          raise "foodName is nil"
        end

        token = get_token_from_headers con.request.headers
        if token == Nil
          con.response.status_code = 401
          con.response.print "{\"message\":\"Missing or invalid JWT Token\"}"
          return
        end
        claims = decode_token token.as(String)

        if uid != claims["uid"] && !claims["admin"]
          con.response.status_code = 401
          con.response.print "{\"message\":\"Not allowed to update this item\"}"
          return
        end

        db.update_quantity uid, food_name, quantity
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
        if food_name.nil?
          raise "foodName is nil"
        end

        token = get_token_from_headers con.request.headers
        if token == Nil
          con.response.status_code = 401
          con.response.print "{\"message\":\"Missing or invalid JWT Token\"}"
          return
        end
        claims = decode_token token.as(String)

        if uid != claims["uid"] && !claims["admin"]
          con.response.status_code = 401
          con.response.print "{\"message\":\"Not allowed to update this item\"}"
          return
        end

        db.remove_item uid, food_name
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
        token = get_token_from_headers con.request.headers
        if token == Nil
          con.response.status_code = 401
          con.response.print "{\"message\":\"Missing or invalid JWT Token\"}"
          return
        end
        claims = decode_token token.as(String)

        order_list = db.get_order_list(claims["uid"].as_i).to_json

        con.response.status_code = 200
        con.response.print order_list
      rescue exception
        con.response.status_code = 500
        con.response.print "{\"message\":\"An error occured #{exception.message}\"}"
      end
    when "DELETE"
      begin
        token = get_token_from_headers con.request.headers
        if token == Nil
          con.response.status_code = 401
          con.response.print "{\"message\":\"Missing or invalid JWT Token\"}"
          return
        end
        claims = decode_token token.as(String)

        order_list = db.clear_list claims["uid"].as_i

        con.response.status_code = 200
        con.response.print "{\"message\":\"Cleared order list\"}"
      rescue exception
        con.response.status_code = 500
        con.response.print "{\"message\":\"An error occured #{exception.message}\"}"
      end
    else
      con.response.status_code = 405
      con.response.print "{\"message\":\"Method is not allowed\"}"
    end
  end

  def submit(con : Context, db : DuckDb)
    case con.request.method
    when "POST"
      begin
        token = get_token_from_headers con.request.headers
        if token == Nil
          con.response.status_code = 401
          con.response.print "{\"message\":\"Missing or invalid JWT Token\"}"
          return
        end
        claims = decode_token token.as(String)

        order_list = db.get_order_list claims["uid"].as_i
        if order_list.size > 0
          publish_items claims["uid"].as_i, order_list.to_json
          db.clear_list claims["uid"].as_i
          con.response.status_code = 202
          con.response.print "{\"message\":\"Accepted items for order see http://localhost:8080/order-manager/order\"}"
        else
          con.response.status_code = 403
          con.response.print "{\"message\":\"There must be at least one item in the order list\"}"
        end
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

def get_token_from_headers(headers : HTTP::Headers)
  if !headers.has_key? "Authorization"
    return Nil
  end

  split = headers["Authorization"].split(' ')
  if split.size < 2
    return Nil
  end

  return split[1]
end
