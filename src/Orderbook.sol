// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {iLayerCCMApp} from "@ilayer/iLayerCCMApp.sol";
import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";
import {IiLayerRouter} from "@ilayer/interfaces/IiLayerRouter.sol";
import {Validator} from "./Validator.sol";
import {TransferUtils} from "./libraries/TransferUtils.sol";

contract Orderbook is Validator, Ownable, iLayerCCMApp {
    using SafeERC20 for IERC20;

    /// @notice storing just the order statuses
    mapping(bytes32 orderId => Status status) public orders;
    /// @notice storing settlers for each chain supported
    mapping(uint256 chain => address settler) public settlers;

    event SettlerUpdated(uint256 indexed chainId, address indexed settler);
    event OrderCreated(bytes32 indexed orderId, address caller, Order order, uint16 confirmations);
    event OrderWithdrawn(bytes32 indexed orderId, address caller);
    event OrderFilled(bytes32 indexed orderId, address indexed filler);

    error InvalidOrderInputApprovals();
    error InvalidTokenAmount();
    error InvalidOrderSignature();
    error OrderDeadlinesMismatch();
    error OrderExpired();
    error OrderCannotBeWithdrawn();
    error OrderCannotBeFilled();
    error OrderCannotBeSettled();
    error Unauthorized();
    error InvalidSourceChain();
    error InvalidUser();

    constructor(address _router) Validator() Ownable(msg.sender) iLayerCCMApp(_router) {}

    function setSettler(uint256 chain, address settler) external onlyOwner {
        settlers[chain] = settler;

        emit SettlerUpdated(chain, settler);
    }

    /// @notice create on-chain order, don't check the signature
    function createOrder(Order memory order, uint16 confirmations) external payable returns (bytes32) {
        address user = iLayerCCMLibrary.bytes64ToAddress(order.user);
        if (user != msg.sender) revert InvalidUser();

        _checkOrderValidity(order);

        bytes32 orderId = hashOrder(order);
        orders[orderId] = Status.ACTIVE;

        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = iLayerCCMLibrary.bytes64ToAddress(input.tokenAddress);
            if (input.tokenId != type(uint256).max) {
                TransferUtils.transfer(user, address(this), tokenAddress, input.tokenId, input.amount);
            } else {
                IERC20(tokenAddress).safeTransferFrom(user, address(this), input.amount);
            }
        }

        _broadcastOrder(order, msg.value, confirmations);

        emit OrderCreated(orderId, msg.sender, order, confirmations);

        return orderId;
    }

    /// @notice create off-chain order, signature must be valid
    function createOrder(Order memory order, bytes[] memory permits, bytes memory signature, uint16 confirmations)
        external
        payable
        returns (bytes32)
    {
        if (order.inputs.length != permits.length) revert InvalidOrderInputApprovals();
        if (!validateOrder(order, signature)) revert InvalidOrderSignature();

        _checkOrderValidity(order);

        bytes32 orderId = hashOrder(order);
        orders[orderId] = Status.ACTIVE;

        address user = iLayerCCMLibrary.bytes64ToAddress(order.user);
        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = iLayerCCMLibrary.bytes64ToAddress(input.tokenAddress);

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

        _broadcastOrder(order, msg.value, confirmations);

        emit OrderCreated(orderId, msg.sender, order, confirmations);

        return orderId;
    }

    function withdrawOrder(Order memory order) external {
        address user = iLayerCCMLibrary.bytes64ToAddress(order.user);
        // the order can only be withdrawn by the user themselves
        if (user != msg.sender) revert Unauthorized();

        bytes32 orderId = hashOrder(order);
        if (order.deadline > block.timestamp || orders[orderId] != Status.ACTIVE) {
            revert OrderCannotBeWithdrawn();
        }

        orders[orderId] = Status.WITHDRAWN;

        // transfer input assets back to the user
        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = iLayerCCMLibrary.bytes64ToAddress(input.tokenAddress);
            if (input.tokenId != type(uint256).max) {
                TransferUtils.transfer(address(this), user, tokenAddress, input.tokenId, input.amount);
            } else {
                IERC20(tokenAddress).safeTransfer(user, input.amount);
            }
        }

        emit OrderWithdrawn(orderId, msg.sender);
    }

    /// @notice receive order settlement message from the settler contract
    function _receiveMessageFromNonPeer(
        address, /*dispatcher*/
        iLayerMessage calldata, /*message*/
        bytes calldata messageData,
        bytes calldata /*extraData*/
    ) internal override onlyRouter {
        (Order memory order, address filler, address fundingWallet) = abi.decode(messageData, (Order, address, address));

        // we don't check anything here (deadline, filler) cause we assume the Settler contract has done that already
        bytes32 orderId = hashOrder(order);
        if (orders[orderId] != Status.ACTIVE) revert OrderCannotBeFilled();
        orders[orderId] = Status.FILLED;

        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = iLayerCCMLibrary.bytes64ToAddress(input.tokenAddress);
            if (input.tokenId != type(uint256).max) {
                TransferUtils.transfer(address(this), fundingWallet, tokenAddress, input.tokenId, input.amount);
            } else {
                IERC20(tokenAddress).safeTransfer(fundingWallet, input.amount);
            }
        }

        emit OrderFilled(orderId, filler);
    }

    function _checkOrderValidity(Order memory order) internal view {
        if (order.sourceChainSelector != block.chainid) revert InvalidSourceChain();
        if (order.inputs[0].amount == 0) revert InvalidTokenAmount();
        if (settlers[order.destinationChainSelector] == address(0)) revert OrderCannotBeSettled();

        if (order.primaryFillerDeadline > order.deadline) revert OrderDeadlinesMismatch();
        if (block.timestamp > order.deadline) revert OrderExpired();
    }

    function _broadcastOrder(Order memory order, uint256 fee, uint16 confirmations) internal {
        bytes memory data = abi.encode(order);
        bytes64 memory dest = iLayerCCMLibrary.addressToBytes64(settlers[order.destinationChainSelector]);
        router.sendMessage{value: fee}(dest, order.destinationChainSelector, confirmations, data);
    }
}
