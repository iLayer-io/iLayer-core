// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Validator} from "../../src/Validator.sol";
import {Orderbook} from "../../src/Orderbook.sol";
import {Settler} from "../../src/Settler.sol";

contract MockScUser is IERC1271 {
    Orderbook internal immutable orderbook;
    Settler internal immutable settler;

    constructor(Orderbook _orderbook, Settler _settler) {
        orderbook = _orderbook;
        settler = _settler;
    }

    function placeOrder(Validator.Order memory order) external {
        //orderbook.createOrder(order);
    }

    function settleOrder(Validator.Order memory order) external {
        //settler.fillOrder(order);
    }

    function isValidSignature(bytes32 orderDigest, bytes memory signature)
        external
        view
        override
        returns (bytes4 magicValue)
    {
        if (ECDSA.recover(orderDigest, signature) == address(this)) {
            magicValue = 0x1626ba7e;
        }
    }
}
