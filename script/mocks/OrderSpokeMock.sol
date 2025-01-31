// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OAppCore, OAppSender, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {BytesUtils} from "../../src/libraries/BytesUtils.sol";
import {Root} from "../../src/Root.sol";
import {Executor} from "../../src/Executor.sol";
import {OrderHubMock} from "./OrderHubMock.sol";

contract OrderSpokeMock is Root, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    uint16 public constant MAX_RETURNDATA_COPY_SIZE = 32;
    Executor public immutable executor;
    mapping(bytes32 => bool) public ordersFilled;
    address public hub;

    event OrderFilled(bytes32 indexed orderId, Order indexed order, address indexed caller, MessagingReceipt receipt);
    event TokenSweep(address indexed token, address indexed caller, uint256 amount);
    event PositiveSlippage(bytes32 indexed orderId, uint256 amount, uint256 receivedAmount);

    error OrderCannotBeFilled();
    error OrderExpired();
    error RestrictedToPrimaryFiller();
    error ExternalCallFailed();

    constructor(address _hub) Ownable(msg.sender) {
        hub = _hub;
        executor = new Executor();
    }

    function sweep(address to, address token) external onlyOwner {
        IERC20 spuriousToken = IERC20(token);
        uint256 amount = spuriousToken.balanceOf(address(this));
        spuriousToken.safeTransfer(to, amount);

        emit TokenSweep(to, token, amount);
    }

    function estimateFee(uint32, bytes memory, bytes calldata) public view returns (uint256) {
        return block.timestamp;
    }

    function fillOrder(
        Order memory order,
        uint64 orderNonce,
        bytes32 fundingWallet,
        uint256 maxGas,
        uint256 gasValue,
        bytes calldata
    ) external payable returns (MessagingReceipt memory) {
        bytes32 orderId = getOrderId(order, orderNonce);

        _validateOrder(order, orderId);
        _transferFunds(order, orderId);

        if (order.callData.length > 0) {
            _callHook(order, maxGas, gasValue);
        }

        ordersFilled[orderId] = true;

        bytes memory payload = abi.encode(order, orderNonce, fundingWallet);
        OrderHubMock(hub).receiveCall(payload);
        MessagingReceipt memory receipt;

        emit OrderFilled(orderId, order, msg.sender, receipt);

        return receipt;
    }

    function _validateOrder(Order memory order, bytes32 orderId) internal view {
        uint64 currentTime = uint64(block.timestamp);
        if (currentTime > order.deadline) revert OrderExpired();
        if (ordersFilled[orderId]) revert OrderCannotBeFilled();

        address filler = BytesUtils.bytes32ToAddress(order.filler);
        if (filler != address(0) && currentTime <= order.primaryFillerDeadline && filler != msg.sender) {
            revert RestrictedToPrimaryFiller();
        }
    }

    function _callHook(Order memory order, uint256 maxGas, uint256 gasValue) internal {
        address callRecipient = BytesUtils.bytes32ToAddress(order.callRecipient);
        bool successful =
            executor.exec{value: gasValue}(callRecipient, maxGas, gasValue, MAX_RETURNDATA_COPY_SIZE, order.callData);
        if (!successful) revert ExternalCallFailed();
    }

    function _transferFunds(Order memory order, bytes32 orderId) internal {
        address to = BytesUtils.bytes32ToAddress(order.user);
        for (uint256 i = 0; i < order.outputs.length; i++) {
            Token memory output = order.outputs[i];

            address tokenAddress = BytesUtils.bytes32ToAddress(output.tokenAddress);

            if (output.tokenType == Type.ERC20) {
                uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
                _transfer(output.tokenType, address(this), to, tokenAddress, output.tokenId, balance);
                if (balance > output.amount) emit PositiveSlippage(orderId, output.amount, balance);
            } else {
                _transfer(output.tokenType, address(this), to, tokenAddress, output.tokenId, output.amount);
            }
        }
    }
}
