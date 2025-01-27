// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {
    IOAppOptionsType3, EnforcedOptionParam
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IOFT, SendParam, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import {Root} from "../src/Root.sol";
import {Validator} from "../src/Validator.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {MockERC1155} from "./mocks/MockERC1155.sol";
import {SmartContractUser} from "./mocks/SmartContractUser.sol";

contract BaseTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    // chain eids
    uint32 public aEid = 1;
    uint32 public bEid = 2;
    bytes[] public permits;

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

    constructor() {
        permits = new bytes[](1);
        permits[0] = "";

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
        vm.label(address(this), "THIS");
        vm.label(address(contractUser), "CONTRACT USER");
        vm.label(address(inputToken), "INPUT TOKEN");
        vm.label(address(inputERC721Token), "INPUT ERC721 TOKEN");
        vm.label(address(inputERC1155Token), "INPUT ERC1155 TOKEN");
        vm.label(address(outputToken), "OUTPUT TOKEN");
    }

    function setUp() public virtual override {
        super.setUp();

        setUpEndpoints(2, LibraryType.UltraLightNode);

        hub = OrderHub(_deployOApp(type(OrderHub).creationCode, abi.encode(address(endpoints[aEid]))));
        spoke = OrderSpoke(_deployOApp(type(OrderSpoke).creationCode, abi.encode(address(endpoints[bEid]))));

        address[] memory oapps = new address[](2);
        oapps[0] = address(hub);
        oapps[1] = address(spoke);
        this.wireOApps(oapps);

        vm.label(address(hub), "HUB");
        vm.label(address(spoke), "SPOKE");
        vm.label(address(spoke.executor()), "EXECUTOR");

        hub.setMaxOrderDeadline(1 days);
    }

    function _getLzData(
        Root.Order memory order,
        uint64 orderNonce,
        uint64 maxGas,
        string memory originFundingWallet,
        string memory destFundingWallet
    ) internal view returns (uint256, bytes memory, bytes memory) {
        // Settle
        bytes memory returnOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(1e8, 0); // B -> A
        bytes memory payloadSettle = abi.encode(order, orderNonce, originFundingWallet);
        uint256 settleFee = spoke.estimateFee(aEid, payloadSettle, returnOptions);

        // Fill
        bytes memory options =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(2 * 1e8 + maxGas, uint128(settleFee)); // A -> B
        bytes memory payloadFill =
            abi.encode(order, orderNonce, maxGas, originFundingWallet, destFundingWallet, returnOptions);
        uint256 fillFee = hub.estimateFee(bEid, payloadFill, options);

        return (fillFee, options, returnOptions);
    }

    function buildOrderRequest(Root.Order memory order, uint64 nonce)
        public
        view
        returns (OrderHub.OrderRequest memory)
    {
        OrderHub.OrderRequest memory request =
            OrderHub.OrderRequest({order: order, deadline: uint64(block.timestamp + 1 days), nonce: nonce});
        return request;
    }

    function buildOrder(
        address user,
        address filler,
        address fromToken,
        uint256 inputAmount,
        address toToken,
        uint256 outputAmount,
        uint256 primaryFillerDeadlineOffset,
        uint256 deadlineOffset,
        address callRecipient,
        bytes memory callData
    ) public view returns (Root.Order memory) {
        // Construct input/output token arrays
        Root.Token[] memory inputs = new Root.Token[](1);
        inputs[0] = Root.Token({
            tokenType: Root.Type.ERC20,
            tokenAddress: Strings.toChecksumHexString(fromToken),
            tokenId: 0,
            amount: inputAmount
        });

        Root.Token[] memory outputs = new Root.Token[](1);
        outputs[0] = Root.Token({
            tokenType: Root.Type.ERC20,
            tokenAddress: Strings.toChecksumHexString(toToken),
            tokenId: 0,
            amount: outputAmount
        });

        // Build the order struct
        return Root.Order({
            user: Strings.toChecksumHexString(user),
            filler: Strings.toChecksumHexString(filler),
            inputs: inputs,
            outputs: outputs,
            sourceChainEid: aEid,
            destinationChainEid: bEid,
            sponsored: false,
            primaryFillerDeadline: uint64(block.timestamp + primaryFillerDeadlineOffset),
            deadline: uint64(block.timestamp + deadlineOffset),
            callRecipient: Strings.toChecksumHexString(callRecipient),
            callData: callData
        });
    }

    function buildSignature(Validator.Order memory order, uint256 user_pk) public view returns (bytes memory) {
        // Hash the order
        bytes32 structHash = hub.hashOrder(order);

        // Compute the EIP-712 domain separator as the contract does
        bytes32 domainSeparator = hub.DOMAIN_SEPARATOR();

        // Create the EIP-712 typed data hash
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Sign this EIP-712 digest using Foundry's vm.sign(...)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user_pk, digest);

        // Pack (r, s, v) into a 65-byte signature
        return abi.encodePacked(r, s, v);
    }

    function validateOrderWasFilled(address user, address filler, uint256 inputAmount, uint256 outputAmount)
        public
        view
    {
        // OrderHub is empty
        assertEq(inputToken.balanceOf(address(hub)), 0, "OrderHub contract is not empty");
        assertEq(outputToken.balanceOf(address(hub)), 0, "OrderHub contract is not empty");
        // User has received the desired tokens
        assertEq(inputToken.balanceOf(user), 0, "User still holds input tokens");
        assertEq(outputToken.balanceOf(user), outputAmount, "User didn't receive output tokens");
        // Filler has received their payment
        assertEq(inputToken.balanceOf(filler), inputAmount, "Filler didn't receive input tokens");
        assertEq(outputToken.balanceOf(filler), 0, "Filler still holds output tokens");
        // Executor contract is empty
        assertEq(inputToken.balanceOf(address(spoke)), 0, "OrderSpoke contract is not empty");
        assertEq(outputToken.balanceOf(address(spoke)), 0, "OrderSpoke contract is not empty");
    }
}

/*

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
*/
