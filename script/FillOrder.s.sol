// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {Root} from "../src/Root.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {BaseScript} from "./BaseScript.sol";

contract FillOrderScript is BaseScript {
    using OptionsBuilder for bytes;

    function run(uint64 nonce) external broadcastTx(fillerPrivateKey) {
        Root.Order memory order = buildOrder();

        MockERC20 token = MockERC20(toToken);
        token.mint(filler, outputAmount);
        token.approve(address(spoke), outputAmount);

        string memory fillerStr = Strings.toChecksumHexString(filler);
        (uint256 fee, bytes memory options, bytes memory returnOptions) =
            _getLzData(order, nonce, 0, fillerStr, fillerStr);
        hub.fillOrder{value: fee}(order, nonce, fillerStr, fillerStr, 0, options, returnOptions);
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
        uint256 settleFee = spoke.estimateFee(sourceEid, payloadSettle, returnOptions);

        // Fill
        bytes memory options =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(2 * 1e8 + maxGas, uint128(settleFee)); // A -> B
        bytes memory payloadFill =
            abi.encode(order, orderNonce, maxGas, originFundingWallet, destFundingWallet, returnOptions);
        uint256 fillFee = hub.estimateFee(destEid, payloadFill, options);

        return (fillFee, options, returnOptions);
    }
}
