// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {EquitoApp} from "@equito-network/EquitoApp.sol";
import {bytes64, EquitoMessage, EquitoMessageLibrary} from "@equito-network/libraries/EquitoMessageLibrary.sol";
import {Validator} from "./Validator.sol";
import {TransferUtils} from "./libraries/TransferUtils.sol";

contract Orderbook is Validator, EquitoApp {
    using SafeERC20 for IERC20;

    mapping(bytes32 orderId => Status status) public orders;

    event OrderCreated(
        bytes32 indexed orderId, address caller, address user, uint256 primaryFillerDeadline, uint256 deadline
    );
    event OrderWithdrawn(bytes32 indexed orderId, address caller);
    event OrderFilled(bytes32 indexed orderId, address caller, address indexed filler);

    error InvalidOrderSignature();
    error OrderDeadlinesMismatch();
    error OrderExpired();
    error OrderCannotBeWithdrawn();
    error OrderCannotBeFilled();
    error Unauthorized();
    error InvalidSourceChain();
    error InvalidMessage();

    constructor(address router) EquitoApp(router) {}

    function createOrder(Order memory order, bytes memory permit) external {
        if (!validateOrder(order)) revert InvalidOrderSignature();
        if (!validateChain(order)) revert InvalidSourceChain();

        if (order.primaryFillerDeadline > order.deadline) revert OrderDeadlinesMismatch();
        if (block.timestamp > order.deadline) revert OrderExpired();

        bytes32 orderId = hashOrder(order);
        orders[orderId] = Status.ACTIVE;

        address user = EquitoMessageLibrary.bytes64ToAddress(order.user);
        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = EquitoMessageLibrary.bytes64ToAddress(input.tokenAddress);

            if (permit.length > 0) {
                // Decode the permit signature and call permit on the token
                (uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
                    abi.decode(permit, (uint256, uint256, uint8, bytes32, bytes32));

                IERC20Permit(tokenAddress).permit(user, address(this), value, deadline, v, r, s);
            }

            if (input.tokenId != type(uint256).max) {
                TransferUtils.transfer(user, address(this), tokenAddress, input.tokenId, input.amount);
            } else {
                IERC20(tokenAddress).safeTransferFrom(user, address(this), input.amount);
            }
        }

        emit OrderCreated(orderId, msg.sender, user, order.primaryFillerDeadline, order.deadline);
    }

    function withdrawOrder(Order memory order) external {
        if (!validateOrder(order)) revert InvalidOrderSignature();

        address user = EquitoMessageLibrary.bytes64ToAddress(order.user);
        if (user != msg.sender) revert Unauthorized();

        bytes32 orderId = hashOrder(order);
        if (order.deadline > block.timestamp || orders[orderId] != Status.ACTIVE) {
            revert OrderCannotBeWithdrawn();
        }
        orders[orderId] = Status.WITHDRAWN;

        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = EquitoMessageLibrary.bytes64ToAddress(input.tokenAddress);
            if (input.tokenId != type(uint256).max) {
                TransferUtils.transfer(address(this), user, tokenAddress, input.tokenId, input.amount);
            } else {
                IERC20(tokenAddress).safeTransfer(user, input.amount);
            }
        }

        emit OrderWithdrawn(orderId, msg.sender);
    }

    function _receiveMessageFromPeer(EquitoMessage calldata message, bytes calldata messageData) internal override {
        if (message.destinationChainSelector != block.chainid) revert InvalidMessage();
        if (
            EquitoMessageLibrary.bytes64ToAddress(bytes64(message.receiver.lower, message.receiver.upper))
                != address(this)
        ) revert InvalidMessage();

        (Order memory order, address filler) = abi.decode(messageData, (Order, address));
        _fillOrder(order, filler);
    }

    function _fillOrder(Order memory order, address filler) internal {
        if (!validateOrder(order)) revert InvalidOrderSignature();

        // we don't check any deadline here cause we assume the Settler contract has done that already
        bytes32 orderId = hashOrder(order);
        if (orders[orderId] != Status.ACTIVE) revert OrderCannotBeFilled();
        orders[orderId] = Status.FILLED;

        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = EquitoMessageLibrary.bytes64ToAddress(input.tokenAddress);
            if (input.tokenId != type(uint256).max) {
                TransferUtils.transfer(address(this), filler, tokenAddress, input.tokenId, input.amount);
            } else {
                IERC20(tokenAddress).safeTransfer(filler, input.amount);
            }
        }

        emit OrderFilled(orderId, msg.sender, filler);
    }
}
