// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Root} from "../src/Root.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";

contract BaseScript is Script {
    OrderHub public hub = OrderHub(vm.envAddress("HUB_ADDRESS"));
    OrderSpoke public spoke = OrderSpoke(vm.envAddress("SPOKE_ADDRESS"));
    address user = vm.envAddress("USER_ADDRESS");
    uint256 userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
    address filler = vm.envAddress("FILLER_ADDRESS");
    uint256 fillerPrivateKey = vm.envUint("FILLER_PRIVATE_KEY");
    address fromToken = vm.envAddress("FROM_TOKEN_ADDRESS");
    uint256 inputAmount = vm.envUint("INPUT_AMOUNT");
    address toToken = vm.envAddress("TO_TOKEN_ADDRESS");
    uint256 outputAmount = vm.envUint("OUTPUT_AMOUNT");
    uint64 fillerDeadlineOffset = uint64(vm.envUint("FILLER_DEADLINE_OFFSET"));
    uint64 mainDeadlineOffset = uint64(vm.envUint("MAIN_DEADLINE_OFFSET"));
    uint32 sourceEid = uint32(vm.envUint("SOURCE_EID"));
    uint32 destEid = uint32(vm.envUint("DEST_EID"));

    modifier broadcastTx(uint256 key) {
        vm.startBroadcast(key);
        _;
        vm.stopBroadcast();
    }

    function buildOrder() public view returns (Root.Order memory) {
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

        return Root.Order({
            user: Strings.toChecksumHexString(user),
            filler: Strings.toChecksumHexString(filler),
            inputs: inputs,
            outputs: outputs,
            sourceChainEid: uint32(sourceEid),
            destinationChainEid: uint32(destEid),
            sponsored: false,
            primaryFillerDeadline: uint64(block.timestamp + fillerDeadlineOffset),
            deadline: uint64(block.timestamp + mainDeadlineOffset),
            callRecipient: Strings.toChecksumHexString(address(0)),
            callData: ""
        });
    }

    function buildSignature(Root.Order memory order) public view returns (bytes memory) {
        bytes32 structHash = hub.hashOrder(order);
        bytes32 domainSeparator = hub.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
