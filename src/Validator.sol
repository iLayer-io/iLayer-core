// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Strings} from "./libraries/Strings.sol";
import {Root} from "./Root.sol";

contract Validator is Root {
    bytes32 public constant TOKEN_TYPEHASH =
        keccak256("Token(uint8 tokenType,string tokenAddress,uint256 tokenId,uint256 amount)");
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        abi.encodePacked(
            "Order(",
            "string user,",
            "string filler,",
            "bytes32 inputsHash,",
            "bytes32 outputsHash,",
            "uint256 sourceChainSelector,",
            "uint256 destinationChainSelector,",
            "bool sponsored,",
            "uint256 primaryFillerDeadline,",
            "uint256 deadline,",
            "string callRecipient,",
            "bytes callData",
            ")"
        )
    );
    bytes32 public constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,address verifyingContract,uint256 chainId)");
    bytes32 public immutable DOMAIN_SEPARATOR;

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("iLayer")), // name
                keccak256(bytes("1")), // version
                address(this), // verifyingContract
                block.chainid // chainId
            )
        );
    }

    function hashTokenStruct(Token memory token) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                TOKEN_TYPEHASH,
                uint8(token.tokenType),
                keccak256(bytes(token.tokenAddress)),
                token.tokenId,
                token.amount
            )
        );
    }

    function hashTokenArray(Token[] memory tokens) internal pure returns (bytes32) {
        bytes32[] memory tokenHashes = new bytes32[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenHashes[i] = hashTokenStruct(tokens[i]);
        }
        return keccak256(abi.encodePacked(tokenHashes));
    }

    function hashOrder(Order memory order) public pure returns (bytes32) {
        bytes32 inputsHash = hashTokenArray(order.inputs);
        bytes32 outputsHash = hashTokenArray(order.outputs);

        return keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                keccak256(bytes(order.user)),
                keccak256(bytes(order.filler)),
                inputsHash,
                outputsHash,
                order.sourceChainSelector,
                order.destinationChainSelector,
                order.sponsored,
                order.primaryFillerDeadline,
                order.deadline,
                keccak256(bytes(order.callRecipient)),
                keccak256(order.callData)
            )
        );
    }

    function validateOrder(Order memory order, bytes memory signature) public view returns (bool) {
        bytes32 structHash = hashOrder(order);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        address orderSigner = Strings.parseAddress(order.user);

        return SignatureChecker.isValidSignatureNow(orderSigner, digest, signature);
    }
}
