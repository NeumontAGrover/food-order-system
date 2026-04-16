docker compose stop
yes | docker compose rm

docker rmi food-order-system-entrance-api
docker rmi food-order-system-orderlist
docker rmi food-order-system-menu
docker rmi food-order-system-authentication

docker compose up -d
