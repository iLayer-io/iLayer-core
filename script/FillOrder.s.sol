// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {Root} from "../src/Root.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {BytesUtils} from "../src/libraries/BytesUtils.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {BaseScript} from "./BaseScript.sol";

contract FillOrderScript is BaseScript {
    using OptionsBuilder for bytes;

    function run() external {
        uint64 nonce = 1;

        deployContracts();
        Root.Order memory order = buildOrder();

        vm.startBroadcast(fillerPrivateKey);
        outputToken.mint(filler, outputAmount);
        outputToken.transfer(address(spoke), outputAmount);

        bytes32 fillerEncoded = BytesUtils.addressToBytes32(filler);
        (uint256 fee, bytes memory options) = getLzData(order, nonce, fillerEncoded);
        spoke.fillOrder{value: fee}(order, nonce, fillerEncoded, 0, 0, options);
        verifyPackets(aEid, BytesUtils.addressToBytes32(address(hub)));
        vm.stopBroadcast();
    }
}
