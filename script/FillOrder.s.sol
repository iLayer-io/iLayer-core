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

    function run(uint64 nonce, uint64 maxGas) external broadcastTx(fillerPrivateKey) {
        Root.Order memory order = buildOrder();

        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(spoke), outputAmount);

        bytes32 fillerEncoded = BytesUtils.addressToBytes32(filler);
        (uint256 fee, bytes memory options) = _getLzData(order, nonce, fillerEncoded);
        spoke.fillOrder{value: fee}(order, nonce, fillerEncoded, maxGas, 0, options);
    }

    function _getLzData(Root.Order memory order, uint64 orderNonce, bytes32 hubFundingWallet)
        internal
        view
        returns (uint256, bytes memory)
    {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(1e8, 0); // Hub -> Spoke
        bytes memory payload = abi.encode(order, orderNonce, hubFundingWallet);
        uint256 fee = spoke.estimateFee(aEid, payload, options);

        return (fee, options);
    }
}
