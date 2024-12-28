// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Validator} from "../../src/Validator.sol";
import {Orderbook} from "../../src/Orderbook.sol";

contract SmartContractUser {
    function approve(IERC20 token, address spender, uint256 amount) external {
        token.approve(spender, amount);
    }

    function createOrder(
        Orderbook orderbook,
        Validator.Order memory order,
        bytes[] memory permits,
        bytes memory signature,
        uint16 confirmations
    ) external {
        orderbook.createOrder(order, permits, signature, confirmations);
    }

    function isValidSignature(bytes32 orderDigest, bytes memory signature) external view returns (bytes4 magicValue) {
        return 0x1626ba7e;
    }
}
