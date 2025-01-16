// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {iLayerCCMApp} from "@ilayer/iLayerCCMApp.sol";
import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";
import {Validator} from "./Validator.sol";
import {Caller} from "./Caller.sol";

/**
 * @title Executor contract
 * @dev Contract that manages order fill and output token transfer from the solver to the user
 * @custom:security-contact security@ilayer.io
 */
contract Executor is Validator, Ownable2Step, ReentrancyGuard, iLayerCCMApp {
    using SafeERC20 for IERC20;

    struct FillParams {
        bytes32 orderId;
        address filler;
        address fundingWallet;
        uint256 maxGas;
        uint16 confirmations;
        uint256 fee;
    }

    uint16 public constant MAX_RETURNDATA_COPY_SIZE = 32;

    Caller public immutable caller;
    /// @notice storing just the order statuses
    mapping(bytes32 => bool) public orders;
    /// @notice storing orderhubs for each chain supported
    mapping(uint256 chainid => address orderhub) public orderhubs;

    event OrderHubUpdated(uint256 indexed chain, address indexed oldOrderHub, address indexed newOrderHub);
    event OrderFilled(bytes32 indexed orderId, address indexed filler);
    event CallDataFailed(bytes32 indexed orderId);

    error InsufficientFeesPaid();
    error InvalidOrderSignature();
    error OrderCannotBeSettled();
    error OrderExpired();
    error OrderAlreadyFilled();
    error RestrictedToPrimaryFiller();
    error ExternalCallFailed();
    error InvalidSender();
    error UnprocessableOrder();

    constructor(address _router) Validator() Ownable(msg.sender) iLayerCCMApp(_router) {
        caller = new Caller();
    }

    function setOrderHub(uint256 chain, address orderhub) external onlyOwner {
        emit OrderHubUpdated(chain, orderhubs[chain], orderhub);

        orderhubs[chain] = orderhub;
    }

    /// @notice receive fill order message from the orderhub contract
    function _receiveMessageFromNonPeer(
        address dispatcher,
        iLayerMessage calldata message,
        bytes calldata messageData,
        bytes calldata extraData
    ) internal override nonReentrant {
        (Order memory order, uint256 orderNonce) = abi.decode(messageData, (Order, uint256));
        _checkOrderValidity(order, message);

        (address fundingWallet, uint256 maxGas, uint256 fee, uint16 confirmations) =
            abi.decode(extraData, (address, uint256, uint256, uint16));

        bytes32 orderId = getOrderId(order, orderNonce);

        // Check and mark the order as filled
        _checkOrderAndMarkFilled(order, orderId, dispatcher);

        // Transfer tokens to the user
        _transferFunds(order, iLayerCCMLibrary.bytes64ToAddress(order.user), dispatcher);

        FillParams memory fillParams = FillParams({
            orderId: orderId,
            filler: dispatcher,
            fundingWallet: fundingWallet,
            maxGas: maxGas,
            confirmations: confirmations,
            fee: fee
        });
        _sendSettleMsgToOrderHub(order, fillParams);
    }

    function _checkOrderValidity(Order memory order, iLayerMessage calldata message) internal view {
        address sender = iLayerCCMLibrary.bytes64ToAddress(message.sender);
        address orderhub = orderhubs[order.sourceChainSelector];

        if (orderhub == address(0)) revert OrderCannotBeSettled();
        if (orderhub != sender) revert InvalidSender();

        if (
            order.sourceChainSelector != message.sourceChainSelector
                || order.destinationChainSelector != message.destinationChainSelector
                || message.destinationChainSelector != block.chainid
        ) revert UnprocessableOrder();
    }

    function _checkOrderAndMarkFilled(Order memory order, bytes32 orderId, address dispatcher) internal {
        if (orders[orderId]) revert OrderAlreadyFilled();

        uint256 currentTime = block.timestamp;
        if (currentTime > order.deadline) revert OrderExpired();

        address filler = iLayerCCMLibrary.bytes64ToAddress(order.filler);
        if (filler != address(0) && currentTime <= order.primaryFillerDeadline && dispatcher != filler) {
            revert RestrictedToPrimaryFiller();
        }

        orders[orderId] = true;
    }

    function _transferFunds(Order memory order, address user, address filler) internal {
        for (uint256 i = 0; i < order.outputs.length;) {
            Token memory output = order.outputs[i];

            address tokenAddress = iLayerCCMLibrary.bytes64ToAddress(output.tokenAddress);
            _transfer(output.tokenType, filler, user, tokenAddress, output.tokenId, output.amount);

            unchecked {
                i++;
            }
        }
    }

    function _sendSettleMsgToOrderHub(Order memory order, FillParams memory fillParams) internal {
        bytes memory data = abi.encode(order, fillParams.fundingWallet);
        bytes64 memory orderhub = iLayerCCMLibrary.addressToBytes64(orderhubs[order.sourceChainSelector]);

        router.sendMessage{value: fillParams.fee}(orderhub, order.sourceChainSelector, fillParams.confirmations, data);

        if (order.callData.length > 0) {
            address callRecipient = iLayerCCMLibrary.bytes64ToAddress(order.callRecipient);

            bool successful = caller.exec(callRecipient, fillParams.maxGas, 0, MAX_RETURNDATA_COPY_SIZE, order.callData);
            if (!successful) revert ExternalCallFailed();
        }

        emit OrderFilled(fillParams.orderId, fillParams.filler);
    }
}
