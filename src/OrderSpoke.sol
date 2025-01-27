// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OApp, Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
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
    mapping(bytes32 => bool) public ordersProcessed;

    event OrderProcessed(bytes32 indexed orderId, Order order, MessagingReceipt receipt);

    error OrderAlreadyProcessed();
    error InvalidSourceChain();
    error ExternalCallFailed();

    constructor(address _router) Ownable(msg.sender) OApp(_router, msg.sender) {
        executor = new Executor();
    }

    function estimateFee(uint32 dstEid, bytes memory payload, bytes calldata options) public view returns (uint256) {
        MessagingFee memory fee = _quote(dstEid, payload, options, false);
        return fee.nativeFee;
    }

    function _lzReceive(Origin calldata origin, bytes32, bytes calldata payload, address, bytes calldata)
        internal
        override
        nonReentrant
    {
        (
            Order memory order,
            uint64 orderNonce,
            uint64 maxGas,
            string memory originFundingWallet,
            string memory destFundingWallet,
            bytes memory returnOptions
        ) = abi.decode(payload, (Order, uint64, uint64, string, string, bytes));

        if (origin.srcEid != order.sourceChainEid) revert InvalidSourceChain();

        /// TODO may not be needed

        // 1. check order exists and hasn't been processed already
        bytes32 orderId = getOrderId(order, orderNonce);
        if (ordersProcessed[orderId]) revert OrderAlreadyProcessed();
        ordersProcessed[orderId] = true;

        // 2. transfer funds from the filler's funding wallet to the user
        address fundingWallet = Strings.parseAddress(destFundingWallet);
        _transferFunds(order, fundingWallet, Strings.parseAddress(order.user));

        // 3. execute an eventual calldata hook
        if (order.callData.length > 0) {
            address callRecipient = Strings.parseAddress(order.callRecipient);
            bool successful = executor.exec(callRecipient, maxGas, 0, MAX_RETURNDATA_COPY_SIZE, order.callData);
            if (!successful) revert ExternalCallFailed();
        }

        // 4. send back the settlement message to the order hub to unlock funds
        bytes memory data = abi.encode(order, orderNonce, originFundingWallet);

        /// @dev we cannot send it to the origin funding wallet as it may not be a compatible address
        MessagingReceipt memory receipt =
            _lzSend(order.sourceChainEid, data, returnOptions, MessagingFee(msg.value, 0), payable(fundingWallet));

        emit OrderProcessed(orderId, order, receipt);
    }

    function _transferFunds(Order memory order, address from, address to) internal {
        for (uint256 i = 0; i < order.outputs.length;) {
            Token memory output = order.outputs[i];

            address tokenAddress = Strings.parseAddress(output.tokenAddress);
            _transfer(output.tokenType, from, to, tokenAddress, output.tokenId, output.amount);

            unchecked {
                i++;
            }
        }
    }
}
