// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {iLayerCCMApp} from "@ilayer/iLayerCCMApp.sol";
import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";
import {IiLayerRouter} from "@ilayer/interfaces/IiLayerRouter.sol";
import {PermitHelper} from "./libraries/PermitHelper.sol";
import {Validator} from "./Validator.sol";

contract Orderbook is Validator, Ownable2Step, ReentrancyGuard, iLayerCCMApp {
    /// @notice storing just the order statuses
    mapping(bytes32 orderId => Status status) public orders;
    /// @notice storing settlers for each chain supported
    mapping(uint256 chain => address settler) public settlers;
    uint256 public maxOrderDeadline;

    uint256 public nonce;
    uint256 public timeBuffer;

    event SettlerUpdated(uint256 indexed chainId, address indexed settler);
    event TimeBufferUpdated(uint256 oldTimeBufferVal, uint256 newTimeBufferVal);
    event MaxOrderDeadlineUpdated(uint256 oldDeadline, uint256 newDeadline);
    event OrderCreated(bytes32 indexed orderId, uint256 nonce, address caller, Order order, uint16 confirmations);
    event OrderWithdrawn(bytes32 indexed orderId, address caller);
    event OrderFilled(bytes32 indexed orderId);

    error InvalidOrderInputApprovals();
    error InvalidOrderSignature();
    error InvalidDeadline();
    error OrderDeadlinesMismatch();
    error OrderExpired();
    error OrderCannotBeWithdrawn();
    error OrderCannotBeFilled();
    error OrderCannotBeSettled();
    error Unauthorized();
    error InvalidSender();
    error InvalidUser();
    error InvalidSourceChain();
    error UnprocessableOrder();

    constructor(address _router) Validator() Ownable(msg.sender) iLayerCCMApp(_router) {
        maxOrderDeadline = 1 days;
    }

    function setSettler(uint256 chain, address settler) external onlyOwner {
        settlers[chain] = settler;

        emit SettlerUpdated(chain, settler);
    }

    function setTimeBuffer(uint256 newTimeBuffer) external onlyOwner {
        emit TimeBufferUpdated(timeBuffer, newTimeBuffer);

        timeBuffer = newTimeBuffer;
    }

    function setMaxOrderDeadline(uint256 newMaxOrderDeadline) external onlyOwner {
        emit MaxOrderDeadlineUpdated(maxOrderDeadline, newMaxOrderDeadline);
        maxOrderDeadline = newMaxOrderDeadline;
    }

    /// @notice create off-chain order, signature must be valid
    function createOrder(Order memory order, bytes[] memory permits, bytes memory signature, uint16 confirmations)
        external
        payable
        nonReentrant
        returns (bytes32, uint256)
    {
        if (order.inputs.length != permits.length) revert InvalidOrderInputApprovals();
        if (order.deadline > block.timestamp + maxOrderDeadline) revert InvalidDeadline();
        if (!validateOrder(order, signature)) revert InvalidOrderSignature();
        if (settlers[order.destinationChainSelector] == address(0)) revert OrderCannotBeSettled();
        if (order.primaryFillerDeadline > order.deadline) revert OrderDeadlinesMismatch();
        if (block.timestamp >= order.deadline) revert OrderExpired();
        if (order.sourceChainSelector != block.chainid) revert InvalidSourceChain();

        uint256 orderNonce = ++nonce; // increment the nonce to guarantee order uniqueness
        bytes32 orderId = getOrderId(order, orderNonce);
        orders[orderId] = Status.ACTIVE;

        address user = iLayerCCMLibrary.bytes64ToAddress(order.user);
        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = iLayerCCMLibrary.bytes64ToAddress(input.tokenAddress);

            if (permits[i].length > 0) {
                // Decode the permit signature and call permit on the token
                (uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
                    abi.decode(permits[i], (uint256, uint256, uint8, bytes32, bytes32));

                PermitHelper.trustlessPermit(tokenAddress, user, address(this), value, deadline, v, r, s);
            }

            _transfer(input.tokenType, user, address(this), tokenAddress, input.tokenId, input.amount);
        }

        _broadcastOrder(order, msg.value, confirmations);

        emit OrderCreated(orderId, orderNonce, msg.sender, order, confirmations);

        return (orderId, orderNonce);
    }

    function withdrawOrder(Order memory order, uint256 orderNonce) external nonReentrant {
        address user = iLayerCCMLibrary.bytes64ToAddress(order.user);
        // the order can only be withdrawn by the user themselves
        if (user != msg.sender) revert Unauthorized();

        bytes32 orderId = getOrderId(order, orderNonce);
        if (order.deadline + timeBuffer > block.timestamp || orders[orderId] != Status.ACTIVE) {
            revert OrderCannotBeWithdrawn();
        }

        orders[orderId] = Status.WITHDRAWN;

        // transfer input assets back to the user
        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = iLayerCCMLibrary.bytes64ToAddress(input.tokenAddress);
            _transfer(input.tokenType, address(this), user, tokenAddress, input.tokenId, input.amount);
        }

        emit OrderWithdrawn(orderId, msg.sender);
    }

    /// @notice receive order settlement message from the settler contract
    function _receiveMessageFromNonPeer(
        address, /*dispatcher*/
        iLayerMessage calldata message,
        bytes calldata messageData,
        bytes calldata /*extraData*/
    ) internal override onlyRouter nonReentrant {
        (Order memory order, uint256 orderNonce, address filler, address fundingWallet) =
            abi.decode(messageData, (Order, uint256, address, address));

        _checkOrderValidity(order, message);

        // we don't check anything here (deadline, filler) cause we assume the Settler contract has done that already
        bytes32 orderId = getOrderId(order, orderNonce);

        if (orders[orderId] != Status.ACTIVE) revert OrderCannotBeFilled();
        orders[orderId] = Status.FILLED;

        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = iLayerCCMLibrary.bytes64ToAddress(input.tokenAddress);
            _transfer(input.tokenType, address(this), fundingWallet, tokenAddress, input.tokenId, input.amount);
        }

        emit OrderFilled(orderId);
    }

    function _checkOrderValidity(Order memory order, iLayerMessage calldata message) internal view {
        address sender = iLayerCCMLibrary.bytes64ToAddress(message.sender);
        if (settlers[message.sourceChainSelector] != sender) revert InvalidSender();

        if (
            order.sourceChainSelector != message.destinationChainSelector
                || order.destinationChainSelector != message.sourceChainSelector
                || message.destinationChainSelector != block.chainid
        ) revert UnprocessableOrder();
    }

    function _broadcastOrder(Order memory order, uint256 fee, uint16 confirmations) internal {
        bytes memory data = abi.encode(order);
        bytes64 memory dest = iLayerCCMLibrary.addressToBytes64(settlers[order.destinationChainSelector]);
        router.sendMessage{value: fee}(dest, order.destinationChainSelector, confirmations, data);
    }
}
