// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OAppCore, OAppSender, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {BytesUtils} from "./libraries/BytesUtils.sol";
import {Root} from "./Root.sol";
import {Executor} from "./Executor.sol";

/**
 * @title OrderSpoke contract
 * @dev Contract that manages order fill and output token transfer from the solver to the user
 * @custom:security-contact security@ilayer.io
 */
contract OrderSpoke is Root, ReentrancyGuard, OAppSender {
    using SafeERC20 for IERC20;

    uint16 public constant MAX_RETURNDATA_COPY_SIZE = 32;
    Executor public immutable executor;
    mapping(bytes32 => bool) public ordersFilled;

    event OrderFilled(bytes32 indexed orderId, Order indexed order, address indexed caller, MessagingReceipt receipt);

    error OrderCannotBeFilled();
    error OrderExpired();
    error RestrictedToPrimaryFiller();
    error ExternalCallFailed();

    constructor(address _router) Ownable(msg.sender) OAppCore(_router, msg.sender) {
        executor = new Executor();
    }

    function estimateFee(uint32 dstEid, bytes memory payload, bytes calldata options) public view returns (uint256) {
        MessagingFee memory fee = _quote(dstEid, payload, options, false);
        return fee.nativeFee;
    }

    function fillOrder(
        Order memory order,
        uint64 orderNonce,
        bytes32 hubFundingWallet,
        bytes32 spokeFundingWallet,
        uint256 maxGas,
        uint256 gasValue,
        bytes calldata options
    ) external payable returns (MessagingReceipt memory) {
        bytes32 orderId = getOrderId(order, orderNonce);

        _validateOrder(order, orderId);
        _transferFunds(order, spokeFundingWallet);

        if (order.callData.length > 0) {
            _callHook(order, maxGas, gasValue);
        }

        ordersFilled[orderId] = true;

        bytes memory payload = abi.encode(order, orderNonce, hubFundingWallet);
        MessagingReceipt memory receipt =
            _lzSend(order.sourceChainEid, payload, options, MessagingFee(msg.value, 0), payable(msg.sender));

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

    function _transferFunds(Order memory order, bytes32 spokeFundingWallet) internal {
        address from = BytesUtils.bytes32ToAddress(spokeFundingWallet);
        address to = BytesUtils.bytes32ToAddress(order.user);

        for (uint256 i = 0; i < order.outputs.length;) {
            Token memory output = order.outputs[i];

            address tokenAddress = BytesUtils.bytes32ToAddress(output.tokenAddress);
            _transfer(output.tokenType, from, to, tokenAddress, output.tokenId, output.amount);

            unchecked {
                i++;
            }
        }
    }
}
