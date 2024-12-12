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
    event OrderFilled(bytes32 indexed orderId, address indexed caller, address indexed filler);

    error InvalidOrderInputApprovals();
    error InvalidTokenAmount();
    error InvalidOrderSignature();
    error OrderDeadlinesMismatch();
    error OrderExpired();
    error OrderCannotBeWithdrawn();
    error OrderCannotBeFilled();
    error Unauthorized();
    error InvalidSourceChain();
    error InvalidUser();
    error InvalidMessage();

    constructor(address _signer, address _router) Validator(_signer) EquitoApp(_router) {}

    function createOrder(Order memory order) external returns (bytes32) {
        address user = EquitoMessageLibrary.bytes64ToAddress(order.user);
        if (user != msg.sender) revert InvalidUser();
        _checkOrder(order);

        bytes32 orderId = hashOrder(order);
        orders[orderId] = Status.ACTIVE;

        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = EquitoMessageLibrary.bytes64ToAddress(input.tokenAddress);
            if (input.tokenId != type(uint256).max) {
                TransferUtils.transfer(user, address(this), tokenAddress, input.tokenId, input.amount);
            } else {
                IERC20(tokenAddress).safeTransferFrom(user, address(this), input.amount);
            }
        }

        emit OrderCreated(orderId, msg.sender, user, order.primaryFillerDeadline, order.deadline);

        return orderId;
    }

    function createOrder(Order memory order, bytes[] memory permits, bytes memory signature)
        external
        returns (bytes32)
    {
        if (order.inputs.length != permits.length) revert InvalidOrderInputApprovals();
        return _processOrder(order, permits, signature);
    }

    function _checkOrder(Order memory order) internal {
        if (!validateChain(order)) revert InvalidSourceChain();
        if (order.inputs[0].amount == 0) revert InvalidTokenAmount();

        if (order.primaryFillerDeadline > order.deadline) revert OrderDeadlinesMismatch();
        if (block.timestamp > order.deadline) revert OrderExpired();
    }

    function _processOrder(Order memory order, bytes[] memory permits, bytes memory signature)
        internal
        returns (bytes32)
    {
        if (order.inputs.length != permits.length) revert InvalidOrderInputApprovals();
        if (!validateOrder(order, signature)) revert InvalidOrderSignature();

        _checkOrder(order);

        bytes32 orderId = hashOrder(order);
        orders[orderId] = Status.ACTIVE;

        address user = EquitoMessageLibrary.bytes64ToAddress(order.user);
        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = EquitoMessageLibrary.bytes64ToAddress(input.tokenAddress);

            if (permits[i].length > 0) {
                // Decode the permit signature and call permit on the token
                (uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
                    abi.decode(permits[i], (uint256, uint256, uint8, bytes32, bytes32));

                IERC20Permit(tokenAddress).permit(user, address(this), value, deadline, v, r, s);
            }

            if (input.tokenId != type(uint256).max) {
                TransferUtils.transfer(user, address(this), tokenAddress, input.tokenId, input.amount);
            } else {
                IERC20(tokenAddress).safeTransferFrom(user, address(this), input.amount);
            }
        }

        emit OrderCreated(orderId, msg.sender, user, order.primaryFillerDeadline, order.deadline);

        return orderId;
    }

    function withdrawOrder(Order memory order) external {
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

    function _receiveMessageFromPeer(EquitoMessage calldata, /*message*/ bytes calldata messageData)
        internal
        override
    {
        (Order memory order, address filler) = abi.decode(messageData, (Order, address));
        _fillOrder(order, filler);
    }

    function _fillOrder(Order memory order, address filler) internal {
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
