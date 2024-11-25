// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OrderUtils} from "./libraries/OrderUtils.sol";
import {TransferUtils} from "./libraries/TransferUtils.sol";
import {Strings} from "./libraries/Strings.sol";

contract Settler {
    using SafeERC20 for IERC20;

    mapping(bytes32 orderId => bool filled) public orders;

    event OrderFilled(bytes32 indexed orderId, address indexed filler);

    error InvalidOrderSignature();
    error OrderAlreadyFilled();
    error RestrictedToPrimaryFiller();

    function fillOrder(OrderUtils.Order memory order) external {
        if (!OrderUtils.validateOrder(order)) revert InvalidOrderSignature();

        bytes32 orderId = OrderUtils.hashOrder(order);
        if (orders[orderId]) revert OrderAlreadyFilled();
        orders[orderId] = true;

        if (msg.sender != order.filler && block.timestamp > order.primaryFillerDeadline) {
            revert RestrictedToPrimaryFiller();
        }

        for (uint256 i = 0; i < order.outputs.length; i++) {
            OrderUtils.Value memory output = order.outputs[i];

            address tokenAddress = Strings.parseAddress(output.tokenAddress);
            if (output.tokenId != type(uint256).max) {
                TransferUtils.transfer(order.filler, order.user, tokenAddress, output.tokenId, output.amount);
            } else {
                IERC20(tokenAddress).safeTransferFrom(order.filler, order.user, output.amount);
            }
        }

        emit OrderFilled(orderId, msg.sender);
    }
}
