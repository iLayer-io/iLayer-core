// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OrderUtils} from "./libraries/OrderUtils.sol";
import {TransferUtils} from "./libraries/TransferUtils.sol";
import {Strings} from "./libraries/Strings.sol";

contract Orderbook {
    using SafeERC20 for IERC20;

    mapping(bytes32 orderId => OrderUtils.Status status) public orders;

    event OrderCreated(
        bytes32 indexed orderId,
        address creator,
        address user,
        uint256 primaryFillerDeadline,
        uint256 deadline,
        string destinationChain
    );
    event OrderWithdrawn(bytes32 indexed orderId, address user);

    error InvalidOrderSignature();
    error OrderDeadlinesMismatch();
    error OrderExpired();
    error OrderCannotBeWithdrawn();
    error Unauthorized();

    function createOrder(OrderUtils.Order memory order) external {
        if (!OrderUtils.validateOrder(order)) revert InvalidOrderSignature();

        if (order.primaryFillerDeadline > order.deadline) revert OrderDeadlinesMismatch();
        if (block.timestamp > order.deadline) revert OrderExpired();

        bytes32 orderId = OrderUtils.hashOrder(order);
        orders[orderId] = OrderUtils.Status.ACTIVE;

        for (uint256 i = 0; i < order.inputs.length; i++) {
            OrderUtils.Value memory input = order.inputs[i];

            address tokenAddress = Strings.parseAddress(input.tokenAddress);

            if (input.tokenId != type(uint256).max) {
                TransferUtils.transfer(order.user, address(this), tokenAddress, input.tokenId, input.amount);
            } else {
                IERC20(tokenAddress).safeTransferFrom(order.user, address(this), input.amount);
            }
        }

        emit OrderCreated(
            orderId, msg.sender, order.user, order.primaryFillerDeadline, order.deadline, order.destinationChain
        );
    }

    function withdrawOrder(OrderUtils.Order memory order) external {
        if (!OrderUtils.validateOrder(order)) revert InvalidOrderSignature();
        if (order.user != msg.sender) revert Unauthorized();

        bytes32 orderId = OrderUtils.hashOrder(order);
        if (order.deadline < block.timestamp || orders[orderId] != OrderUtils.Status.ACTIVE) {
            revert OrderCannotBeWithdrawn();
        }
        orders[orderId] = OrderUtils.Status.WITHDRAWN;

        for (uint256 i = 0; i < order.inputs.length; i++) {
            OrderUtils.Value memory input = order.inputs[i];

            address tokenAddress = Strings.parseAddress(input.tokenAddress);
            if (input.tokenId != type(uint256).max) {
                TransferUtils.transfer(address(this), order.user, tokenAddress, input.tokenId, input.amount);
            } else {
                IERC20(tokenAddress).safeTransfer(order.user, input.amount);
            }
        }

        emit OrderWithdrawn(orderId, msg.sender);
    }
}
