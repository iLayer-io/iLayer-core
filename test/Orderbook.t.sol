// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {MockERC20} from "./MockERC20.sol";

contract OrderbookTest is Test {
    Orderbook public immutable orderbook;
    MockERC20 public immutable inputToken;
    MockERC20 public immutable outputToken;

    constructor() {
        orderbook = new Orderbook();
        inputToken = new MockERC20("input", "INPUT");
        outputToken = new MockERC20("output", "OUTPUT");
    }

    function testCreateOrder() external {
        //orderbook.createOrder();
    }
}
