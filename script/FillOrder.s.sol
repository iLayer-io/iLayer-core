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

        MockERC20 token = MockERC20(toToken);
        token.mint(filler, outputAmount);
        token.approve(address(spoke), outputAmount);

        bytes32 fillerEncoded = BytesUtils.addressToBytes32(filler);
        (uint256 fee, bytes memory options, bytes memory returnOptions) =
            _getLzData(order, nonce, 0, fillerEncoded, fillerEncoded);
        spoke.fillOrder{value: fee}(order, nonce, fillerEncoded, fillerEncoded, maxGas, options, returnOptions);
    }

    function _getLzData(
        Root.Order memory order,
        uint64 orderNonce,
        uint64 maxGas,
        bytes32 hubFundingWallet,
        bytes32 spokeFundingWallet
    ) internal view returns (uint256, bytes memory, bytes memory) {
        // Settle
        bytes memory returnOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(1e8, 0); // Hub -> Spoke
        bytes memory payloadSettle = abi.encode(order, orderNonce, maxGas, spokeFundingWallet);
        uint256 settleFee = hub.estimateFee(destEid, payloadSettle, returnOptions);

        // Fill
        bytes memory options =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(2 * 1e8 + maxGas, uint128(settleFee)); // Spoke -> Hub
        bytes memory payloadFill =
            abi.encode(order, orderNonce, maxGas, hubFundingWallet, spokeFundingWallet, returnOptions);
        uint256 fillFee = spoke.estimateFee(sourceEid, payloadFill, options);

        return (fillFee, options, returnOptions);
    }
}
