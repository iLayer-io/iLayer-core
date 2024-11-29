// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {bytes64, EquitoMessage, EquitoMessageLibrary} from "@equito-network/libraries/EquitoMessageLibrary.sol";
import {ExcessivelySafeCall} from "@safecall/ExcessivelySafeCall.sol";
import {Validator} from "./Validator.sol";
import {TransferUtils} from "./libraries/TransferUtils.sol";
import {IEquitoRouter} from "./interfaces/IEquitoRouter.sol";

contract Settler is Validator, Ownable {
    using SafeERC20 for IERC20;
    using ExcessivelySafeCall for address;

    IEquitoRouter public immutable router;
    mapping(bytes32 orderId => bool filled) public orders;
    mapping(uint256 chain => address orderbook) public orderbooks;

    event OrderbookUpdated(uint256 indexed chain, address indexed orderbook);
    event OrderFilled(bytes32 indexed orderId, address indexed caller, address indexed filler);
    event CallDataExecuted(bytes32 indexed orderId, bool status, bytes message);
    event CallDataFailed(bytes32 indexed orderId);

    error InsufficientFeesPaid();
    error InvalidOrderSignature();
    error OrderCannotBeSettled();
    error OrderExpired();
    error OrderAlreadyFilled();
    error RestrictedToPrimaryFiller();

    constructor(address _router) Ownable(msg.sender) {
        router = IEquitoRouter(_router);
    }

    function setOrderbook(uint256 chain, address orderbook) external onlyOwner {
        orderbooks[chain] = orderbook;

        emit OrderbookUpdated(chain, orderbook);
    }

    function fillOrder(Order memory order) external payable {
        if (!validateOrder(order)) revert InvalidOrderSignature();
        if (router.getFee(address(this)) < msg.value) revert InsufficientFeesPaid();

        if (orderbooks[order.sourceChainSelector] == address(0)) revert OrderCannotBeSettled();

        bytes32 orderId = hashOrder(order);
        if (orders[orderId]) revert OrderAlreadyFilled();

        if (block.timestamp > order.deadline) revert OrderExpired();

        address user = EquitoMessageLibrary.bytes64ToAddress(order.user);
        address filler = EquitoMessageLibrary.bytes64ToAddress(order.filler);

        // Check if a specific filler is assigned
        if (filler != address(0)) {
            // If the filler is assigned, only the filler can settle before the primaryFillerDeadline
            if (block.timestamp <= order.primaryFillerDeadline && msg.sender != filler) {
                revert RestrictedToPrimaryFiller();
            }
        }

        orders[orderId] = true;

        for (uint256 i = 0; i < order.outputs.length; i++) {
            Token memory output = order.outputs[i];

            address tokenAddress = EquitoMessageLibrary.bytes64ToAddress(output.tokenAddress);
            if (output.tokenId != type(uint256).max) {
                TransferUtils.transfer(filler, user, tokenAddress, output.tokenId, output.amount);
            } else {
                IERC20(tokenAddress).safeTransferFrom(msg.sender, user, output.amount);
            }
        }

        bytes memory data = abi.encode(order, msg.sender);
        bytes64 memory dest = EquitoMessageLibrary.addressToBytes64(orderbooks[order.sourceChainSelector]);
        router.sendMessage{value: msg.value}(bytes64(dest.lower, dest.upper), order.sourceChainSelector, data);

        if (order.callData.length > 0) {
            address callRecipient = EquitoMessageLibrary.bytes64ToAddress(order.callRecipient);
            (bool success, bytes memory result) = callRecipient.excessivelySafeCall(
                1200, // TODO fix this
                0,
                32,
                order.callData
            );

            emit CallDataExecuted(orderId, success, result);
        }

        emit OrderFilled(orderId, msg.sender, filler);
    }
}
