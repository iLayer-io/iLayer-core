// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {BytesUtils} from "./libraries/BytesUtils.sol";
import {Root} from "./Root.sol";

contract Validator is Root {
    /**
     * @dev EIP712 typehashes
     *
     * Notice that we:
     *   - Use `uint8 tokenType` in the Token type string because enum
     *     is not directly supported; we pass it as a uint8 in `abi.encode()`.
     *   - Use `bytes32 tokenAddress` in the type string because that's the struct field type.
     *   - Exclude `filler` and `primaryFillerDeadline` from ORDER_TYPEHASH to ensure
     *     they are not part of the user-signed data.
     */
    bytes32 public constant TOKEN_TYPEHASH =
        keccak256("Token(uint8 tokenType,bytes32 tokenAddress,uint256 tokenId,uint256 amount)");

    /**
     * @dev
     *  Because we have an array of `Token` (inputs and outputs),
     *  we typically reference the sub-struct type as `Token[]`. In the "raw" EIP712 typed data,
     *  you'd see something like:
     *
     *     "Order(bytes32 user,Token[] inputs,Token[] outputs,uint32 sourceChainEid,
     *            uint32 destinationChainEid,bool sponsored,uint64 deadline,
     *            bytes32 callRecipient,bytes callData)
     *      Token(uint8 tokenType,bytes32 tokenAddress,uint256 tokenId,uint256 amount)"
     *
     *  However, when encoding in Solidity, we'll manually hash each array of Tokens
     *  (i.e. `inputsHash`, `outputsHash`), so we represent them in the final type string
     *  as `bytes32 inputsHash` and `bytes32 outputsHash`.
     *
     *  This is a standard approach for nested arrays in EIP-712, but remember to inline
     *  the sub-type definition in the final type string.
     */
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        abi.encodePacked(
            "Order(",
            "bytes32 user,",
            "bytes32 inputsHash,",
            "bytes32 outputsHash,",
            "uint32 sourceChainEid,",
            "uint32 destinationChainEid,",
            "bool sponsored,",
            "uint64 deadline,",
            "bytes32 callRecipient,",
            "bytes callData",
            ")",
            "Token(uint8 tokenType,bytes32 tokenAddress,uint256 tokenId,uint256 amount)"
        )
    );

    /**
     * @dev EIP712 Domain Separator
     */
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

    /**
     * @dev Compute the EIP712 struct hash of a single `Token`.
     *      - Use `uint8(token.tokenType)` since enum => uint8.
     *      - Use `token.tokenAddress` directly (no extra keccak256).
     */
    function hashTokenStruct(Token memory token) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(TOKEN_TYPEHASH, uint8(token.tokenType), token.tokenAddress, token.tokenId, token.amount)
        );
    }

    /**
     * @dev Hash an array of Tokens by computing each Token's struct-hash,
     *      then keccak256 of the packed array of those hashes.
     */
    function hashTokenArray(Token[] memory tokens) internal pure returns (bytes32) {
        bytes32[] memory tokenHashes = new bytes32[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenHashes[i] = hashTokenStruct(tokens[i]);
        }
        return keccak256(abi.encodePacked(tokenHashes));
    }

    /**
     * @dev Compute the EIP712 struct hash of the `Order`.
     *
     * IMPORTANT:
     *   - We do NOT include `filler` or `primaryFillerDeadline` in this hash,
     *     because they are excluded from user signing.
     *   - We pass `hashTokenArray(order.inputs)` and `hashTokenArray(order.outputs)`
     *     as separate fields (inputsHash, outputsHash).
     */
    function hashOrder(Order memory order) public pure returns (bytes32) {
        bytes32 inputsHash = hashTokenArray(order.inputs);
        bytes32 outputsHash = hashTokenArray(order.outputs);

        return keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                order.user, // bytes32 user
                inputsHash, // bytes32 inputsHash
                outputsHash, // bytes32 outputsHash
                order.sourceChainEid, // uint32 sourceChainEid
                order.destinationChainEid, // uint32 destinationChainEid
                order.sponsored, // bool sponsored
                order.deadline, // uint64 deadline
                order.callRecipient, // bytes32 callRecipient
                keccak256(order.callData) // hashed bytes callData
            )
        );
    }

    /**
     * @dev Validate the order signature according to EIP712.
     *      The signer is assumed to be `order.user` (converted from bytes32 => address).
     *
     * NOTE: For a real implementation, you'd need a proper BytesUtils.bytes32ToAddress
     *       and a SignatureChecker library. The code below is illustrative.
     */
    function validateOrder(Order memory order, bytes memory signature) public view returns (bool) {
        // 1. Hash the order into EIP712 struct hash
        bytes32 structHash = hashOrder(order);

        // 2. Build the final signed message per EIP-712
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        // 3. Recover or check signature against the user (cast from bytes32 -> address).
        address orderSigner = BytesUtils.bytes32ToAddress(order.user);
        //return isValidSignatureNow(orderSigner, digest, signature);
        return SignatureChecker.isValidSignatureNow(orderSigner, digest, signature);
    }
}
