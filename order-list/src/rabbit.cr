require "amqp-client"
require "./duck_db"

include AMQP

module RabbitClient
  def publish_items(uid : Int, items_json : String)
    Client.start "amqp://guest:guest@rabbitmq:5672" do |cl|
      cl.channel do |ch|
        queue = ch.queue "order_list"
        queue.publish items_json
      end
    end
  end
end
