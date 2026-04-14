curl -X POST http://localhost:45854/order -d '{"foodName":"lasagna","price":18,"quantity":9}'; echo
curl -X POST http://localhost:45854/order -d '{"foodName":"salad","price":12.7,"quantity":1}'; echo
curl -X POST http://localhost:45854/order -d '{"foodName":"soup","price":23.55,"quantity":2}'; echo

curl http://localhost:45854/order-list
echo; read

curl -X PATCH http://localhost:45854/order -d '{"foodName":"soup","quantity":5}'; echo
curl -X PATCH http://localhost:45854/order -d '{"foodName":"salad","quantity":2}'; echo

curl http://localhost:45854/order-list
echo; read

curl -X DELETE http://localhost:45854/order -d '{"foodName":"lasagna"}'; echo

curl http://localhost:45854/order-list
echo; read

curl -X DELETE http://localhost:45854/order-list; echo

curl http://localhost:45854/order-list
echo; read
