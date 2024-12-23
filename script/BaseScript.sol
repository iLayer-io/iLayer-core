// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";
import {iLayerRouter, IiLayerRouter} from "@ilayer/iLayerRouter.sol";
import {Validator} from "../src/Validator.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {MockRouter} from "../test/mocks/MockRouter.sol";

contract BaseScript is Script {
    bytes public constant msgProof = abi.encode(1);

    Orderbook public orderbook = Orderbook(vm.envAddress("ORDERBOOK_ADDRESS"));
    MockRouter public router = MockRouter(vm.envAddress("ROUTER_ADDRESS"));
    address settler = vm.envAddress("SETTLER_ADDRESS");
    uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
    address user = vm.envAddress("USER_ADDRESS");
    address filler = vm.envAddress("FILLER_ADDRESS");
    address fromToken = vm.envAddress("FROM_TOKEN_ADDRESS");
    uint256 inputAmount = vm.envUint("INPUT_AMOUNT");
    address toToken = vm.envAddress("TO_TOKEN_ADDRESS");
    uint256 outputAmount = vm.envUint("OUTPUT_AMOUNT");
    uint256 primaryDeadline = vm.envUint("PRIMARY_DEADLINE");
    uint256 secondaryDeadline = vm.envUint("SECONDARY_DEADLINE");

    function buildOrder() public view returns (Validator.Order memory) {
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

        return Validator.Order({
            user: iLayerCCMLibrary.addressToBytes64(user),
            filler: iLayerCCMLibrary.addressToBytes64(filler),
            inputs: inputs,
            outputs: outputs,
            sourceChainSelector: block.chainid,
            destinationChainSelector: block.chainid,
            sponsored: false,
            primaryFillerDeadline: block.timestamp + primaryDeadline,
            deadline: block.timestamp + secondaryDeadline,
            callRecipient: iLayerCCMLibrary.addressToBytes64(address(0)),
            callData: ""
        });
    }

    function buildSignature(Validator.Order memory order) public view returns (bytes memory) {
        bytes32 structHash = orderbook.hashOrder(order);
        bytes32 domainSeparator = orderbook.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
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
}
