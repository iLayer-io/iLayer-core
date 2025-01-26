// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Strings} from "./libraries/Strings.sol";
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
    mapping(uint256 chainid => address hub) public hubs;

    event HubUpdated(uint256 indexed chainid, address indexed oldHub, address indexed newHub);
    event orderProcessed(bytes32 indexed orderId, Order order);

    error OrderAlreadyProcessed();
    error ExternalCallFailed();

    constructor(address _router) Ownable(msg.sender) OApp(_router, msg.sender) {
        executor = new Executor();
    }

    function setHub(uint256 chain, address hub) external onlyOwner {
        emit HubUpdated(chain, hubs[chain], hub);
        hubs[chain] = hub;
    }

    function _lzReceive(Origin calldata, bytes32, bytes calldata payload, address, bytes calldata)
        internal
        override
        nonReentrant
    {
        (Order memory order, uint256 orderNonce, string memory fundingWalletStr, uint256 maxGas) =
            abi.decode(payload, (Order, uint256, string, uint256));

        /*
        address orderhub = orderhubs[order.sourceChainEid];

        if (orderhub == address(0)) revert OrderCannotBeSettled();
        if (orderhub != sender) revert InvalidSender();

        if (
            order.sourceChainSelector != message.sourceChainSelector
                || order.destinationChainSelector != message.destinationChainSelector
                || message.destinationChainSelector != block.chainid
        ) revert UnprocessableOrder();
        */

        // 1. check order exists and hasn't been processed already
        bytes32 orderId = getOrderId(order, orderNonce);
        if (ordersProcessed[orderId]) revert OrderAlreadyProcessed();
        ordersProcessed[orderId] = true;

        // 2. transfer funds from the filler's funding wallet to the user
        address fundingWallet = Strings.parseAddress(fundingWalletStr);
        _transferFunds(order, fundingWallet, Strings.parseAddress(order.user));

        // 3. execute an eventual calldata hook
        if (order.callData.length > 0) {
            address callRecipient = Strings.parseAddress(order.callRecipient);
            bool successful = executor.exec(callRecipient, maxGas, 0, MAX_RETURNDATA_COPY_SIZE, order.callData);
            if (!successful) revert ExternalCallFailed();
        }

        // 4. send back the settlement message to the order hub to unlock funds
        bytes memory data = abi.encode(order, orderNonce, fundingWalletStr);
        _lzSend(order.sourceChainEid, data, "", MessagingFee(msg.value, 0), payable(msg.sender));

        emit orderProcessed(orderId, order);
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
