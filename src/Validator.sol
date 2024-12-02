// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {bytes64, EquitoMessage, EquitoMessageLibrary} from "@equito-network/libraries/EquitoMessageLibrary.sol";

// https://github.com/hashflownetwork/x-protocol/blob/90a2283435f63a469a22c318b47cdbc87fc6975d/evm/contracts/pools/HashflowPool.sol#L615

contract Validator {
    enum Status {
        ACTIVE,
        FILLED,
        WITHDRAWN
    }

    struct Token {
        bytes64 tokenAddress;
        uint256 tokenId;
        uint256 amount;
    }

    struct Order {
        bytes64 user;
        bytes64 filler;
        Token[] inputs;
        Token[] outputs;
        uint256 sourceChainSelector;
        uint256 destinationChainSelector;
        bool sponsored;
        uint256 primaryFillerDeadline;
        uint256 deadline;
        bytes64 callRecipient;
        bytes callData;
        bytes signature;
    }

    bytes32 public constant TOKEN_TYPEHASH = keccak256("Token(bytes64 tokenAddress,uint256 tokenId,uint256 amount)");
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(bytes64 user,bytes64 filler,bytes32 inputsHash,bytes32 outputsHash,uint256 sourceChainSelector,uint256 destinationChainSelector,bool sponsored,uint256 primaryFillerDeadline,uint256 deadline,bytes64 callRecipient,bytes callData)"
    );
    bytes32 public constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,address verifyingContract,uint256 chainId)");
    address public immutable signer;

    constructor(address _signer) {
        signer = _signer;
    }

    function computeDomainSeparator(uint256 chainId) public view returns (bytes32) {
        return keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, keccak256(bytes("iLayer")), keccak256(bytes("1")), signer, chainId)
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
                order.sourceChainSelector,
                order.destinationChainSelector,
                order.sponsored,
                order.primaryFillerDeadline,
                order.deadline,
                order.callRecipient,
                order.callData
            )
        );
    }

    function validateOrder(Order memory order) public view returns (bool) {
        uint256 chainId = order.sourceChainSelector;
        bytes32 domainSeparator = computeDomainSeparator(chainId);

        bytes32 orderHash = hashOrder(order);
        bytes32 orderDigest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, orderHash));
        address signerAddress = EquitoMessageLibrary.bytes64ToAddress(order.user);

        (address recoveredSigner, ECDSA.RecoverError error,) = ECDSA.tryRecover(orderDigest, order.signature);
        if (error == ECDSA.RecoverError.NoError && recoveredSigner == signerAddress) {
            return true;
        } else {
            // If ECDSA recovery fails, try EIP-1271 for smart contracts
            bytes4 result = IERC1271(signerAddress).isValidSignature(orderDigest, order.signature);
            return result == IERC1271.isValidSignature.selector;
        }
    }

    function validateChain(Order memory order) public view returns (bool) {
        return order.sourceChainSelector == block.chainid;
    }
}
