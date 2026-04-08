docker compose stop
echo y | docker compose rm

docker rmi food-order-system-entrance-api
docker rmi food-order-system-menu

docker compose up -d
