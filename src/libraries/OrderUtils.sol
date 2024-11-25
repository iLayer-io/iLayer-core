// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

library OrderUtils {
    enum Status {
        ACTIVE,
        FILLED,
        WITHDRAWN
    }

    struct Value {
        string tokenAddress;
        uint256 tokenId;
        uint256 amount;
    }

    struct Order {
        address user;
        address filler;
        Value[] inputs;
        Value[] outputs;
        string sourceChain;
        string destinationChain;
        bool sponsored;
        uint256 primaryFillerDeadline;
        uint256 deadline;
        bytes signature;
    }

    bytes32 private constant VALUE_TYPEHASH = keccak256("Value(address tokenAddress,uint256 tokenId,uint256 amount)");
    bytes32 private constant ORDER_TYPEHASH = keccak256(
        "Order(address user,address filler,bytes32 inputsHash,bytes32 outputsHash,string sourceChain,string destinationChain,bool sponsored,uint256 primaryFillerDeadline,uint256 deadline)"
    );

    error InvalidOrderSignature();

    function hashValue(Value memory value) internal pure returns (bytes32) {
        return keccak256(abi.encode(VALUE_TYPEHASH, value.tokenAddress, value.tokenId, value.amount));
    }

    function hashValueArray(Value[] memory values) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](values.length);
        for (uint256 i = 0; i < values.length; i++) {
            hashes[i] = hashValue(values[i]);
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function hashOrder(Order memory order) internal pure returns (bytes32) {
        bytes32 inputsHash = hashValueArray(order.inputs);
        bytes32 outputsHash = hashValueArray(order.outputs);

        return keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                order.user,
                order.filler,
                inputsHash,
                outputsHash,
                keccak256(bytes(order.sourceChain)),
                keccak256(bytes(order.destinationChain)),
                order.sponsored,
                order.primaryFillerDeadline,
                order.deadline
            )
        );
    }

    function validateOrder(Order memory order) public pure returns (bool) {
        bytes32 orderHash = hashOrder(order);
        address signer = ECDSA.recover(orderHash, order.signature);

        return (signer == order.user);
    }
}
