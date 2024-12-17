#!/bin/bash

export RPC_URL=http://127.0.0.1:8545
export DEPLOYER_PUBLIC_KEY=0xa0Ee7A142d267C1f36714E4a8F75612F20a79720
export DEPLOYER_PRIVATE_KEY=0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6

anvil -p 8545 &
ANVIL_PID=$!

cleanup() {
  kill $ANVIL_PID
}
trap cleanup EXIT

sleep 1

ROUTER=$(forge create test/mocks/MockRouter.sol:MockRouter --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY)
export ROUTER_ADDRESS=$(echo "$ROUTER" | grep "Deployed to:" | awk '{print $3}')
ORDERBOOK=$(forge create src/Orderbook.sol:Orderbook --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY --constructor-args $ROUTER_ADDRESS)
export ORDERBOOK_ADDRESS=$(echo "$ORDERBOOK" | grep "Deployed to:" | awk '{print $3}')
SETTLER=$(forge create src/Settler.sol:Settler --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY --constructor-args $ROUTER_ADDRESS)
export SETTLER_ADDRESS=$(echo "$SETTLER" | grep "Deployed to:" | awk '{print $3}')

echo " "
echo "---------------------------------------------------------------------------------"
echo "Mock Router contract deployed to $ROUTER_ADDRESS"
echo "Orderbook contract deployed to $ORDERBOOK_ADDRESS"
echo "Settler contract deployed to $SETTLER_ADDRESS"
echo "---------------------------------------------------------------------------------"

wait $ANVIL_PID
