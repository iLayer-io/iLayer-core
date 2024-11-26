// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Validator} from "../src/Validator.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {Settler} from "../src/Settler.sol";
import {Strings} from "../src/libraries/Strings.sol";
import {MockERC20} from "./MockERC20.sol";

contract BaseTest is Test {
    // users
    uint256 public immutable user0_pk = uint256(keccak256("user0-private-key"));
    address public immutable user0 = vm.addr(user0_pk);
    uint256 public immutable user1_pk = uint256(keccak256("user1-private-key"));
    address public immutable user1 = vm.addr(user1_pk);
    uint256 public immutable user2_pk = uint256(keccak256("user2-private-key"));
    address public immutable user2 = vm.addr(user2_pk);

    // contracts
    Orderbook public immutable orderbook;
    Settler public immutable settler;
    MockERC20 public immutable inputToken;
    MockERC20 public immutable outputToken;

    constructor() {
        orderbook = new Orderbook();
        settler = new Settler();
        inputToken = new MockERC20("input", "INPUT");
        outputToken = new MockERC20("output", "OUTPUT");

        vm.label(user0, "USER0");
        vm.label(user1, "USER1");
        vm.label(user2, "USER2");

        vm.label(address(orderbook), "ORDERBOOK");
        vm.label(address(settler), "SETTLER");
        vm.label(address(inputToken), "INPUT TOKEN");
        vm.label(address(outputToken), "OUTPUT TOKEN");
    }

    function buildOrder(
        uint256 inputAmount,
        uint256 outputAmount,
        address user,
        uint256 user_pk,
        address fromToken,
        address toToken,
        uint256 primaryFillerDeadlineOffset,
        uint256 deadlineOffset
    ) public view returns (Validator.Order memory order) {
        Validator.Token[] memory inputs = new Validator.Token[](1);
        inputs[0] = Validator.Token({
            tokenAddress: Strings.toChecksumHexString(address(fromToken)),
            tokenId: type(uint256).max,
            amount: inputAmount
        });

        Validator.Token[] memory outputs = new Validator.Token[](1);
        outputs[0] = Validator.Token({
            tokenAddress: Strings.toChecksumHexString(address(toToken)),
            tokenId: type(uint256).max,
            amount: outputAmount
        });

        string memory chain = Strings.toString(block.chainid);
        order = Validator.Order({
            user: user,
            filler: address(this),
            inputs: inputs,
            outputs: outputs,
            sourceChain: chain,
            destinationChain: chain,
            sponsored: false,
            primaryFillerDeadline: block.timestamp + primaryFillerDeadlineOffset,
            deadline: block.timestamp + deadlineOffset,
            signature: ""
        });

        // Compute the full EIP-712 digest
        bytes32 orderHash = orderbook.hashOrder(order);
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", orderbook.computeDomainSeparator(block.chainid), orderHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user_pk, digest);
        order.signature = abi.encodePacked(r, s, v);

        return order;
    }
}