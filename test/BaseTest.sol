// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";
import {iLayerRouter, IiLayerRouter} from "@ilayer/iLayerRouter.sol";
import {Validator} from "../src/Validator.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {Settler} from "../src/Settler.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockRouter} from "./mocks/MockRouter.sol";
import {MockScUser} from "./mocks/MockScUser.sol";
import {MockiLayerVerifier} from "./mocks/MockiLayerVerifier.sol";
import {MockiLayerFees} from "./mocks/MockiLayerFees.sol";

contract BaseTest is Test {
    // users
    uint256 public immutable user0_pk = uint256(keccak256("user0-private-key"));
    address public immutable user0 = vm.addr(user0_pk);
    uint256 public immutable user1_pk = uint256(keccak256("user1-private-key"));
    address public immutable user1 = vm.addr(user1_pk);
    uint256 public immutable user2_pk = uint256(keccak256("user2-private-key"));
    address public immutable user2 = vm.addr(user2_pk);

    // iLayer
    MockiLayerVerifier public immutable verifier;
    MockiLayerFees public immutable iLayerFees;
    MockRouter public immutable router;
    address public constant iLayerL1Address = address(0x45717569746f);
    bytes public constant msgProof = abi.encode(1);

    // contracts
    Orderbook public immutable orderbook;
    Settler public immutable settler;
    MockERC20 public immutable inputToken;
    MockERC20 public immutable outputToken;
    MockScUser public immutable contractUser0;
    MockScUser public immutable contractUser1;

    constructor() {
        verifier = new MockiLayerVerifier();
        iLayerFees = new MockiLayerFees();
        router = new MockRouter();
        /* iLayerRouter(
            1, address(verifier), address(iLayerFees), 0, iLayerCCMLibrary.addressToBytes64(iLayerL1Address)
        );*/
        orderbook = new Orderbook(address(router));
        settler = new Settler(address(router));
        inputToken = new MockERC20("input", "INPUT");
        outputToken = new MockERC20("output", "OUTPUT");
        contractUser0 = new MockScUser(orderbook, settler);
        contractUser1 = new MockScUser(orderbook, settler);

        deal(user0, 1 ether);
        deal(user1, 1 ether);
        deal(user2, 1 ether);

        vm.label(user0, "USER0");
        vm.label(user1, "USER1");
        vm.label(user2, "USER2");
        vm.label(address(contractUser0), "CONTRACT_USER0");
        vm.label(address(contractUser1), "CONTRACT_USER1");
        vm.label(address(orderbook), "ORDERBOOK");
        vm.label(address(settler), "SETTLER");
        vm.label(address(inputToken), "INPUT TOKEN");
        vm.label(address(outputToken), "OUTPUT TOKEN");
        vm.label(address(router), "ROUTER");

        orderbook.setSettler(block.chainid, address(settler));
        settler.setOrderbook(block.chainid, address(orderbook));
    }

    function buildOrder(
        address filler,
        uint256 inputAmount,
        uint256 outputAmount,
        address user,
        address fromToken,
        address toToken,
        uint256 primaryFillerDeadlineOffset,
        uint256 deadlineOffset,
        address callRecipient,
        bytes memory callData
    ) public view returns (Validator.Order memory) {
        // Construct input/output token arrays
        Validator.Token[] memory inputs = new Validator.Token[](1);
        inputs[0] = Validator.Token({
            tokenAddress: iLayerCCMLibrary.addressToBytes64(fromToken),
            tokenId: type(uint256).max,
            amount: inputAmount
        });

        Validator.Token[] memory outputs = new Validator.Token[](1);
        outputs[0] = Validator.Token({
            tokenAddress: iLayerCCMLibrary.addressToBytes64(toToken),
            tokenId: type(uint256).max,
            amount: outputAmount
        });

        // Build the order struct
        return Validator.Order({
            user: iLayerCCMLibrary.addressToBytes64(user),
            filler: iLayerCCMLibrary.addressToBytes64(filler),
            inputs: inputs,
            outputs: outputs,
            sourceChainSelector: block.chainid,
            destinationChainSelector: block.chainid,
            sponsored: false,
            primaryFillerDeadline: block.timestamp + primaryFillerDeadlineOffset,
            deadline: block.timestamp + deadlineOffset,
            callRecipient: iLayerCCMLibrary.addressToBytes64(callRecipient),
            callData: callData
        });
    }

    function buildSignature(Validator.Order memory order, uint256 user_pk) public view returns (bytes memory) {
        // Hash the order
        bytes32 structHash = orderbook.hashOrder(order);

        // Compute the EIP-712 domain separator as the contract does
        bytes32 domainSeparator = orderbook.DOMAIN_SEPARATOR();

        // Create the EIP-712 typed data hash
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign this EIP-712 digest using Foundry's vm.sign(...)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user_pk, digest);

        // Pack (r, s, v) into a 65-byte signature
        return abi.encodePacked(r, s, v);
    }

    function buildMessage(address sender, address receiver, bytes memory data)
        public
        view
        returns (iLayerMessage memory)
    {
        return iLayerMessage({
            blockNumber: 1,
            sourceChainSelector: 2,
            blockConfirmations: 0,
            sender: iLayerCCMLibrary.addressToBytes64(sender),
            destinationChainSelector: block.chainid,
            receiver: iLayerCCMLibrary.addressToBytes64(receiver),
            hashedData: keccak256(data)
        });
    }

    function validateOrderWasFilled(address user, address filler, uint256 inputAmount, uint256 outputAmount)
        public
        view
    {
        // Orderbook is empty
        assertEq(inputToken.balanceOf(address(orderbook)), 0, "Orderbook contract is not empty");
        assertEq(outputToken.balanceOf(address(orderbook)), 0, "Orderbook contract is not empty");
        // User has received the desired tokens
        assertEq(inputToken.balanceOf(user), 0, "User still holds input tokens");
        assertEq(outputToken.balanceOf(user), outputAmount, "User didn't receive output tokens");
        // Filler has received their payment
        assertEq(inputToken.balanceOf(filler), inputAmount, "Filler didn't receive input tokens");
        assertEq(outputToken.balanceOf(filler), 0, "Filler still holds output tokens");
        // Settler contract is empty
        assertEq(inputToken.balanceOf(address(settler)), 0, "Settler contract is not empty");
        assertEq(outputToken.balanceOf(address(settler)), 0, "Settler contract is not empty");
    }
}
