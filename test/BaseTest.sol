// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { TestHelper } from "@layerzerolabs/lz-evm-oapp-v2/test/TestHelper.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {Validator} from "../src/Validator.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {SmartContractUser} from "./mocks/SmartContractUser.sol";

contract BaseTest is TestHelper {
    using OptionsBuilder for bytes;

    // users
    uint256 public immutable user0_pk = uint256(keccak256("user0-private-key"));
    address public immutable user0 = vm.addr(user0_pk);
    uint256 public immutable user1_pk = uint256(keccak256("user1-private-key"));
    address public immutable user1 = vm.addr(user1_pk);
    uint256 public immutable user2_pk = uint256(keccak256("user2-private-key"));
    address public immutable user2 = vm.addr(user2_pk);

    // contracts
    OrderHub public hub;
    OrderSpoke public spoke;
    MockERC20 public inputToken;
    MockERC20 public outputToken;
    MockERC721 public inputERC721Token;
    MockERC1155 public inputERC1155Token;
    SmartContractUser public contractUser;

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);
        hub = OrderHub(_deployOApp(type(OrderHub).creationCode, abi.encode(address(this))));
        spoke = OrderSpoke(_deployOApp(type(OrderSpoke).creationCode, abi.encode(address(this))));

        // Configure and wire the OFTs together
        address[] memory ofts = new address[](2);
        ofts[0] = address(aOFT);
        ofts[1] = address(bOFT);
        this.wireOApps(ofts);

        inputToken = new MockERC20("input", "INPUT");
        inputERC721Token = new MockERC721("input", "INPUT");
        inputERC1155Token = new MockERC1155("input");
        outputToken = new MockERC20("output", "OUTPUT");
        contractUser = new SmartContractUser();

        deal(user0, 1 ether);
        deal(user1, 1 ether);
        deal(user2, 1 ether);

        vm.label(user0, "USER0");
        vm.label(user1, "USER1");
        vm.label(user2, "USER2");
        vm.label(address(spoke.executor()), "EXECUTOR");
        vm.label(address(contractUser), "CONTRACT USER");
        vm.label(address(hub), "HUB");
        vm.label(address(spoke), "SPOKE");
        vm.label(address(inputToken), "INPUT TOKEN");
        vm.label(address(inputERC721Token), "INPUT ERC721 TOKEN");
        vm.label(address(inputERC1155Token), "INPUT ERC1155 TOKEN");
        vm.label(address(outputToken), "OUTPUT TOKEN");

        orderhub.setMaxOrderDeadline(1 days);
    }
}

/*
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
            tokenType: Validator.Type.ERC20,
            tokenAddress: iLayerCCMLibrary.addressToBytes64(fromToken),
            tokenId: type(uint256).max,
            amount: inputAmount
        });

        Validator.Token[] memory outputs = new Validator.Token[](1);
        outputs[0] = Validator.Token({
            tokenType: Validator.Type.ERC20,
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

    function buildERC721Order(
        address filler,
        uint256 tokenId,
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
            tokenType: Validator.Type.ERC721,
            tokenAddress: iLayerCCMLibrary.addressToBytes64(fromToken),
            tokenId: tokenId,
            amount: 1
        });

        Validator.Token[] memory outputs = new Validator.Token[](1);
        outputs[0] = Validator.Token({
            tokenType: Validator.Type.ERC20,
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

    function buildERC1155Order(
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
            tokenType: Validator.Type.ERC1155,
            tokenAddress: iLayerCCMLibrary.addressToBytes64(fromToken),
            tokenId: 1,
            amount: inputAmount
        });

        Validator.Token[] memory outputs = new Validator.Token[](1);
        outputs[0] = Validator.Token({
            tokenType: Validator.Type.ERC20,
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
        bytes32 structHash = orderhub.hashOrder(order);

        // Compute the EIP-712 domain separator as the contract does
        bytes32 domainSeparator = orderhub.DOMAIN_SEPARATOR();

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
            sourceChainSelector: block.chainid,
            blockConfirmations: 0,
            sender: iLayerCCMLibrary.addressToBytes64(sender),
            destinationChainSelector: block.chainid,
            receiver: iLayerCCMLibrary.addressToBytes64(receiver),
            hashedData: keccak256(data)
        });
    }

    function buildOrderRequest(Validator.Order memory order, uint256 nonce)
        public
        view
        returns (OrderHub.OrderRequest memory)
    {
        OrderHub.OrderRequest memory request =
            OrderHub.OrderRequest({order: order, deadline: block.timestamp + 1 days, nonce: nonce});
        return request;
    }

    function validateOrderWasFilled(address user, address filler, uint256 inputAmount, uint256 outputAmount)
        public
        view
    {
        // OrderHub is empty
        assertEq(inputToken.balanceOf(address(orderhub)), 0, "OrderHub contract is not empty");
        assertEq(outputToken.balanceOf(address(orderhub)), 0, "OrderHub contract is not empty");
        // User has received the desired tokens
        assertEq(inputToken.balanceOf(user), 0, "User still holds input tokens");
        assertEq(outputToken.balanceOf(user), outputAmount, "User didn't receive output tokens");
        // Filler has received their payment
        assertEq(inputToken.balanceOf(filler), inputAmount, "Filler didn't receive input tokens");
        assertEq(outputToken.balanceOf(filler), 0, "Filler still holds output tokens");
        // Executor contract is empty
        assertEq(inputToken.balanceOf(address(executor)), 0, "Executor contract is not empty");
        assertEq(outputToken.balanceOf(address(executor)), 0, "Executor contract is not empty");
    }
    */
