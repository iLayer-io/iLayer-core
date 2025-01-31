// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
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
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";
import {BytesUtils} from "../src/libraries/BytesUtils.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

contract BaseScript is Script, TestHelperOz5 {
    using OptionsBuilder for bytes;

    OrderHub public hub;
    OrderSpoke public spoke;
    MockERC20 public inputToken;
    MockERC20 public outputToken;
    uint32 public aEid = 1;
    uint32 public bEid = 2;

    address user = vm.envAddress("USER_ADDRESS");
    uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
    address filler = vm.envAddress("FILLER_ADDRESS");
    uint256 fillerPrivateKey = vm.envUint("FILLER_PRIVATE_KEY");
    uint256 inputAmount = vm.envUint("INPUT_AMOUNT");
    uint256 outputAmount = vm.envUint("OUTPUT_AMOUNT");
    uint64 fillerDeadlineOffset = uint64(vm.envUint("FILLER_DEADLINE_OFFSET"));
    uint64 mainDeadlineOffset = uint64(vm.envUint("MAIN_DEADLINE_OFFSET"));

    constructor() {
        fillerDeadlineOffset += uint64(block.timestamp);
        mainDeadlineOffset += uint64(block.timestamp);
    }

    function deployContracts() public {
        this.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        hub = OrderHub(_deployOApp(type(OrderHub).creationCode, abi.encode(address(endpoints[aEid]))));
        spoke = OrderSpoke(_deployOApp(type(OrderSpoke).creationCode, abi.encode(address(endpoints[bEid]))));
        console2.log("hub", address(hub));
        console2.log("spoke", address(spoke));

        inputToken = new MockERC20("input", "INPUT");
        outputToken = new MockERC20("output", "OUTPUT");
        console2.log("inputToken", address(inputToken));
        console2.log("outputToken", address(outputToken));

        spoke.setPeer(aEid, BytesUtils.addressToBytes32(address(hub)));
    }

    function getLzData(Root.Order memory order, uint64 orderNonce, bytes32 hubFundingWallet)
        public
        view
        returns (uint256, bytes memory)
    {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(1e8, 0); // Hub -> Spoke
        bytes memory payload = abi.encode(order, orderNonce, hubFundingWallet);
        uint256 fee = spoke.estimateFee(aEid, payload, options);

        return (fee, options);
    }

    function buildOrder() public view returns (Root.Order memory) {
        Root.Token[] memory inputs = new Root.Token[](1);
        inputs[0] = Root.Token({
            tokenType: Root.Type.ERC20,
            tokenAddress: BytesUtils.addressToBytes32(address(inputToken)),
            tokenId: 0,
            amount: inputAmount
        });

        Root.Token[] memory outputs = new Root.Token[](1);
        outputs[0] = Root.Token({
            tokenType: Root.Type.ERC20,
            tokenAddress: BytesUtils.addressToBytes32(address(outputToken)),
            tokenId: 0,
            amount: outputAmount
        });

        return Root.Order({
            user: BytesUtils.addressToBytes32(user),
            filler: BytesUtils.addressToBytes32(filler),
            inputs: inputs,
            outputs: outputs,
            sourceChainEid: aEid,
            destinationChainEid: bEid,
            sponsored: false,
            primaryFillerDeadline: fillerDeadlineOffset,
            deadline: mainDeadlineOffset,
            callRecipient: "",
            callData: ""
        });
    }

    function buildSignature(Root.Order memory order) public view returns (bytes memory) {
        bytes32 structHash = hub.hashOrder(order);
        bytes32 domainSeparator = hub.domainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
