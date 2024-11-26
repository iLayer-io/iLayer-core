// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Strings} from "./libraries/Strings.sol";

contract Validator {
    enum Status {
        ACTIVE,
        FILLED,
        WITHDRAWN
    }

    struct Token {
        string tokenAddress;
        uint256 tokenId;
        uint256 amount;
    }

    struct Order {
        address user;
        address filler;
        Token[] inputs;
        Token[] outputs;
        string sourceChain;
        string destinationChain;
        bool sponsored;
        uint256 primaryFillerDeadline;
        uint256 deadline;
        bytes signature;
    }

    bytes32 public constant TOKEN_TYPEHASH = keccak256("Token(address tokenAddress,uint256 tokenId,uint256 amount)");
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(address user,address filler,bytes32 inputsHash,bytes32 outputsHash,string sourceChain,string destinationChain,bool sponsored,uint256 primaryFillerDeadline,uint256 deadline)"
    );
    bytes32 public constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,address verifyingContract,uint256 chainId)");

    function computeDomainSeparator(uint256 chainId) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, keccak256(bytes("iLayer")), keccak256(bytes("1")), address(this), chainId
            )
        );
    }

    function hashTokenStruct(Token memory token) internal pure returns (bytes32) {
        return keccak256(abi.encode(TOKEN_TYPEHASH, token.tokenAddress, token.tokenId, token.amount));
    }

    function hashTokenArray(Token[] memory tokens) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            hashes[i] = hashTokenStruct(tokens[i]);
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function hashOrder(Order memory order) public pure returns (bytes32) {
        bytes32 inputsHash = hashTokenArray(order.inputs);
        bytes32 outputsHash = hashTokenArray(order.outputs);

        return keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                order.user,
                order.filler,
                inputsHash,
                outputsHash,
                order.sourceChain,
                order.destinationChain,
                order.sponsored,
                order.primaryFillerDeadline,
                order.deadline
            )
        );
    }

    function validateOrder(Order memory order) public view returns (bool) {
        uint256 chainId = Strings.parseUint(order.sourceChain);
        bytes32 domainSeparator = computeDomainSeparator(chainId);

        bytes32 orderHash = hashOrder(order);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, orderHash));
        address signer = ECDSA.recover(digest, order.signature);

        return (signer == order.user);
    }

    function validateChain(Order memory order) public view returns (bool) {
        return Strings.equal(order.sourceChain, Strings.toString(block.chainid));
    }
}