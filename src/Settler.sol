// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {iLayerCCMApp} from "@ilayer/iLayerCCMApp.sol";
import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";
import {ExcessivelySafeCall} from "@safecall/ExcessivelySafeCall.sol";
import {Validator} from "./Validator.sol";
import {TransferUtils} from "./libraries/TransferUtils.sol";

contract Settler is Validator, Ownable, iLayerCCMApp {
    using SafeERC20 for IERC20;
    using ExcessivelySafeCall for address;

    /// @notice storing just the order statuses
    mapping(bytes32 => bool) public orders;
    /// @notice storing orderbooks for each chain supported
    mapping(uint256 => address) public orderbooks;

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

    constructor(address _router) Validator() Ownable(msg.sender) iLayerCCMApp(_router) {}

    function setOrderbook(uint256 chain, address orderbook) external onlyOwner {
        orderbooks[chain] = orderbook;
        emit OrderbookUpdated(chain, orderbook);
    }

    struct FillParams {
        address dispatcher;
        address fundingWallet;
        uint256 maxGas;
        uint16 confirmations;
        uint256 fee;
    }

    /// @notice receive fill order message from the orderbook contract
    function _receiveMessageFromNonPeer(
        address dispatcher,
        iLayerMessage calldata, /* message */
        bytes calldata messageData,
        bytes calldata extraData
    ) internal override onlyRouter {
        // Decode messageData into `order`
        (Order memory order) = abi.decode(messageData, (Order));
        // Decode extraData
        (address fundingWallet, uint256 maxGas, uint256 fee, uint16 confirmations) =
            abi.decode(extraData, (address, uint256, uint256, uint16));

        if (orderbooks[order.sourceChainSelector] == address(0)) revert OrderCannotBeSettled();

        bytes32 orderId = hashOrder(order);

        // Check and mark the order as filled
        _checkOrderAndMarkFilled(order, orderId, dispatcher);

        // Transfer tokens to the user
        _transferFunds(order, iLayerCCMLibrary.bytes64ToAddress(order.user), fundingWallet);

        FillParams memory fillParams = FillParams({
            dispatcher: dispatcher,
            fundingWallet: fundingWallet,
            maxGas: maxGas,
            confirmations: confirmations,
            fee: fee
        });
        _sendSettleMsgToOrderbook(order, orderId, fillParams);
    }

    function _checkOrderAndMarkFilled(Order memory order, bytes32 orderId, address dispatcher) internal {
        if (orders[orderId]) revert OrderAlreadyFilled();
        if (block.timestamp > order.deadline) revert OrderExpired();

        address filler = iLayerCCMLibrary.bytes64ToAddress(order.filler);
        if (filler != address(0) && block.timestamp <= order.primaryFillerDeadline && dispatcher != filler) {
            revert RestrictedToPrimaryFiller();
        }

        orders[orderId] = true;
    }

    function _transferFunds(Order memory order, address user, address fundingWallet) internal {
        for (uint256 i = 0; i < order.outputs.length; i++) {
            Token memory output = order.outputs[i];

            address tokenAddress = iLayerCCMLibrary.bytes64ToAddress(output.tokenAddress);
            // If tokenId != max, treat as NFT or specialized transfer
            if (output.tokenId != type(uint256).max) {
                TransferUtils.transfer(fundingWallet, user, tokenAddress, output.tokenId, output.amount);
            } else {
                IERC20(tokenAddress).safeTransferFrom(fundingWallet, user, output.amount);
            }
        }
    }

    function _sendSettleMsgToOrderbook(Order memory order, bytes32 orderId, FillParams memory fillParams) internal {
        address filler = iLayerCCMLibrary.bytes64ToAddress(order.filler);
        bytes memory data = abi.encode(order, fillParams.dispatcher, fillParams.fundingWallet);
        bytes64 memory orderbook = iLayerCCMLibrary.addressToBytes64(orderbooks[order.sourceChainSelector]);

        router.sendMessage{value: fillParams.fee}(orderbook, order.sourceChainSelector, fillParams.confirmations, data);

        if (order.callData.length > 0) {
            address callRecipient = iLayerCCMLibrary.bytes64ToAddress(order.callRecipient);
            (bool success, bytes memory result) =
                callRecipient.excessivelySafeCall(fillParams.maxGas, 0, 32, order.callData);

            emit CallDataExecuted(orderId, success, result);
        }

        emit OrderFilled(orderId, fillParams.dispatcher, filler);
    }
}
