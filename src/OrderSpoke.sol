// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OApp, Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {BytesUtils} from "./libraries/BytesUtils.sol";
import {Root} from "./Root.sol";
import {Executor} from "./Executor.sol";

/**
 * @title OrderSpoke contract
 * @dev Contract that manages order fill and output token transfer from the solver to the user
 * @custom:security-contact security@ilayer.io
 */
contract OrderSpoke is Root, ReentrancyGuard, OApp {
    using SafeERC20 for IERC20;

    uint16 public constant MAX_RETURNDATA_COPY_SIZE = 32;
    Executor public immutable executor;
    mapping(bytes32 => bool) public ordersFilled;

    event OrderProcessed(
        bytes32 indexed orderId, Order indexed order, address indexed caller, MessagingReceipt receipt
    );
    event OrderSettled(bytes32 indexed orderId, Order indexed order);

    error OrderCannotBeFilled();
    error OrderExpired();
    error RestrictedToPrimaryFiller();
    error InvalidSourceChain();
    error ExternalCallFailed();

    constructor(address _router) Ownable(msg.sender) OApp(_router, msg.sender) {
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
        uint64 maxGas,
        bytes calldata options,
        bytes calldata returnOptions
    ) external payable returns (MessagingReceipt memory) {
        bytes32 orderId = getOrderId(order, orderNonce);
        if (ordersFilled[orderId]) revert OrderCannotBeFilled();

        uint64 currentTime = uint64(block.timestamp);
        if (currentTime > order.deadline) revert OrderExpired();

        // we only check this here and not on the hub
        address filler = BytesUtils.bytes32ToAddress(order.filler);
        if (filler != address(0) && currentTime <= order.primaryFillerDeadline && filler != msg.sender) {
            revert RestrictedToPrimaryFiller();
        }

        bytes memory payload =
            abi.encode(order, orderNonce, maxGas, hubFundingWallet, spokeFundingWallet, returnOptions);
        MessagingReceipt memory receipt =
            _lzSend(order.sourceChainEid, payload, options, MessagingFee(msg.value, 0), payable(msg.sender));

        emit OrderProcessed(orderId, order, msg.sender, receipt);

        return receipt;
    }

    function _lzReceive(Origin calldata origin, bytes32, bytes calldata payload, address, bytes calldata)
        internal
        override
        nonReentrant
    {
        (Order memory order, uint64 orderNonce, uint64 maxGas, bytes32 spokeFundingWallet) =
            abi.decode(payload, (Order, uint64, uint64, bytes32));

        if (origin.srcEid != order.sourceChainEid) revert InvalidSourceChain();

        /// TODO may not be needed

        // 1. check order exists and hasn't been processed already
        bytes32 orderId = getOrderId(order, orderNonce);
        ordersFilled[orderId] = true;

        // 2. transfer funds from the filler's funding wallet to the user
        address fundingWallet = BytesUtils.bytes32ToAddress(spokeFundingWallet);
        _transferFunds(order, fundingWallet, BytesUtils.bytes32ToAddress(order.user));

        // 3. execute an eventual calldata hook
        if (order.callData.length > 0) {
            address callRecipient = BytesUtils.bytes32ToAddress(order.callRecipient);
            bool successful = executor.exec(callRecipient, maxGas, 0, MAX_RETURNDATA_COPY_SIZE, order.callData);
            if (!successful) revert ExternalCallFailed();
        }

        emit OrderSettled(orderId, order);
    }

    function _transferFunds(Order memory order, address from, address to) internal {
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
