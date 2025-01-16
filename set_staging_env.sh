#!/bin/bash

export RPC_URL=http://127.0.0.1:8545
export DEPLOYER_PUBLIC_KEY=0xa0Ee7A142d267C1f36714E4a8F75612F20a79720
export DEPLOYER_PRIVATE_KEY=0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6
export CHAINID=31337

anvil -p 8545 &
ANVIL_PID=$!

cleanup() {
  kill $ANVIL_PID
}
trap cleanup EXIT

sleep 1

USDC=$(forge create --broadcast test/mocks/MockERC20.sol:MockERC20 --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY --constructor-args "USDC" "USDC")
export USDC_ADDRESS=$(echo "$USDC" | grep "Deployed to:" | awk '{print $3}')
WETH=$(forge create --broadcast test/mocks/MockERC20.sol:MockERC20 --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY --constructor-args "WETH" "WETH")
export WETH_ADDRESS=$(echo "$WETH" | grep "Deployed to:" | awk '{print $3}')
ROUTER=$(forge create --broadcast test/mocks/MockRouter.sol:MockRouter --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY)
export ROUTER_ADDRESS=$(echo "$ROUTER" | grep "Deployed to:" | awk '{print $3}')
ORDERHUB=$(forge create --broadcast src/OrderHub.sol:OrderHub --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY --constructor-args $ROUTER_ADDRESS)
export ORDERHUB_ADDRESS=$(echo "$ORDERHUB" | grep "Deployed to:" | awk '{print $3}')
EXECUTOR=$(forge create --broadcast src/Executor.sol:Executor --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY --constructor-args $ROUTER_ADDRESS)
export EXECUTOR_ADDRESS=$(echo "$EXECUTOR" | grep "Deployed to:" | awk '{print $3}')

cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $ORDERHUB_ADDRESS "setExecutor(uint256,address)" $CHAINID $EXECUTOR_ADDRESS
cast send --rpc-url=$RPC_URL --private-key=$DEPLOYER_PRIVATE_KEY $EXECUTOR_ADDRESS "setOrderHub(uint256,address)" $CHAINID $ORDERHUB_ADDRESS

echo " "
echo "---------------------------------------------------------------------------------"
echo "Mock USDC contract deployed to $USDC_ADDRESS"
echo "Mock WETH contract deployed to $WETH_ADDRESS"
echo "Mock Router contract deployed to $ROUTER_ADDRESS"
echo "OrderHub contract deployed to $ORDERHUB_ADDRESS"
echo "Executor contract deployed to $EXECUTOR_ADDRESS"
echo "---------------------------------------------------------------------------------"

wait $ANVIL_PID
