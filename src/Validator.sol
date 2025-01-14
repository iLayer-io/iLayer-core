// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";

contract Validator {
    using SafeERC20 for IERC20;

    enum Status {
        NULL,
        ACTIVE,
        FILLED,
        WITHDRAWN
    }

    enum Type {
        ERC20,
        ERC721,
        ERC1155
    }

    struct Token {
        Type tokenType;
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
    }

    error UnsupportedTransfer();

    bytes32 public constant TOKEN_TYPEHASH =
        keccak256("Token(uint256 tokenType,bytes64 tokenAddress,uint256 tokenId,uint256 amount)");
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(bytes64 user,bytes64 filler,bytes32 inputsHash,bytes32 outputsHash,uint256 sourceChainSelector,uint256 destinationChainSelector,bool sponsored,uint256 primaryFillerDeadline,uint256 deadline,bytes64 callRecipient,bytes callData)"
    );
    bytes32 public constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,address verifyingContract,uint256 chainId)");
    bytes32 public immutable DOMAIN_SEPARATOR = keccak256(
        abi.encode(
            EIP712_DOMAIN_TYPEHASH, keccak256(bytes("iLayer")), keccak256(bytes("1")), address(this), block.chainid
        )
    );

    function hashTokenStruct(Token memory token) internal pure returns (bytes32) {
        return keccak256(abi.encode(TOKEN_TYPEHASH, token.tokenType, token.tokenAddress, token.tokenId, token.amount));
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

    function getOrderId(Order memory order, uint256 nonce) public pure returns (bytes32) {
        return keccak256(abi.encode(order.user, nonce, order.sourceChainSelector, order.destinationChainSelector));
    }

    function validateOrder(Order memory order, bytes memory signature) public view returns (bool) {
        bytes32 structHash = hashOrder(order);

        // Compute the final EIP-712 digest
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        address orderSigner = iLayerCCMLibrary.bytes64ToAddress(order.user);
        return SignatureChecker.isValidSignatureNow(orderSigner, digest, signature);
    }

    function _transfer(Type tokenType, address from, address to, address token, uint256 id, uint256 amount) internal {
        if (tokenType == Type.ERC20) {
            if (from == address(this)) IERC20(token).safeTransfer(to, amount);
            else IERC20(token).safeTransferFrom(from, to, amount);
        } else if (tokenType == Type.ERC721) {
            IERC721(token).safeTransferFrom(from, to, id);
        } else if (tokenType == Type.ERC1155) {
            IERC1155(token).safeTransferFrom(from, to, id, amount, "");
        } else {
            revert UnsupportedTransfer();
        }
    }
}