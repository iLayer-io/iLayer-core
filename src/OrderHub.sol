// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {OApp, Origin, MessagingFee, MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {Strings} from "./libraries/Strings.sol";
import {PermitHelper} from "./libraries/PermitHelper.sol";
import {Validator} from "./Validator.sol";

/**
 * @title OrderHub contract
 * @dev Contract that stores user orders and input tokens
 * @custom:security-contact security@ilayer.io
 */
contract OrderHub is Validator, ReentrancyGuard, OApp, IERC165, IERC721Receiver, IERC1155Receiver {
    struct OrderRequest {
        uint256 deadline;
        uint256 nonce;
        Order order;
    }

    mapping(bytes32 orderId => Status status) public orders;
    mapping(address user => mapping(uint256 nonce => bool used)) public requestNonces;
    mapping(uint256 chain => address spoke) public spokes;
    uint256 public maxOrderDeadline;
    uint256 public timeBuffer;
    uint256 public nonce;

    event SpokeUpdated(uint256 indexed chainId, address indexed oldSpoke, address indexed newSpoke);
    event TimeBufferUpdated(uint256 oldTimeBufferVal, uint256 newTimeBufferVal);
    event MaxOrderDeadlineUpdated(uint256 oldDeadline, uint256 newDeadline);
    event OrderCreated(bytes32 indexed orderId, uint256 nonce, Order order, address indexed calller);
    event OrderWithdrawn(bytes32 indexed orderId, address indexed caller);
    event OrderFillInitiated(bytes32 indexed orderId, address indexed caller);
    event OrderFilled(bytes32 indexed orderId);
    event ERC721Received(address operator, address from, uint256 tokenId, bytes data);
    event ERC1155Received(address operator, address from, uint256 id, uint256 value, bytes data);
    event ERC1155BatchReceived(address operator, address from, uint256[] ids, uint256[] values, bytes data);

    error RequestNonceReused();
    error RequestExpired();
    error InvalidOrderInputApprovals();
    error InvalidOrderSignature();
    error InvalidDeadline();
    error OrderDeadlinesMismatch();
    error OrderPrimaryFillerExpired();
    error OrderExpired();
    error OrderCannotBeWithdrawn();
    error OrderCannotBeFilled();
    error UnsupportedChain();
    error Unauthorized();
    error InvalidSender();
    error InvalidUser();
    error InvalidSourceChain();
    error UnprocessableOrder();
    error RestrictedToPrimaryFiller();

    constructor(address _router) Ownable(msg.sender) OApp(_router, msg.sender) {
        maxOrderDeadline = 1 days;
    }

    function setSpoke(uint256 chain, address spoke) external onlyOwner {
        emit SpokeUpdated(chain, spokes[chain], spoke);
        spokes[chain] = spoke;
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
    function createOrder(OrderRequest memory request, bytes[] memory permits, bytes memory signature)
        external
        payable
        nonReentrant
        returns (bytes32, uint256)
    {
        Order memory order = request.order;
        address user = Strings.parseAddress(order.user);

        // validate order request
        if (requestNonces[user][request.nonce]) revert RequestNonceReused();
        if (block.timestamp > request.deadline) revert RequestExpired();

        // validate order
        _checkOrderValidity(order, permits, signature);

        requestNonces[user][request.nonce] = true; // mark the nonce as used
        uint256 orderNonce = ++nonce; // increment the nonce to guarantee order uniqueness
        bytes32 orderId = getOrderId(order, orderNonce);
        orders[orderId] = Status.ACTIVE;

        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = Strings.parseAddress(input.tokenAddress);
            if (permits[i].length > 0) {
                _applyPermits(permits[i], user, tokenAddress);
            }

            _transfer(input.tokenType, user, address(this), tokenAddress, input.tokenId, input.amount);
        }

        emit OrderCreated(orderId, orderNonce, order, msg.sender);

        return (orderId, orderNonce);
    }

    function fillOrder(Order memory order, uint256 orderNonce, string memory fundingWallet, uint256 maxGas)
        external
        payable
        returns (MessagingReceipt memory)
    {
        bytes32 orderId = getOrderId(order, orderNonce);
        if (orders[orderId] != Status.ACTIVE) revert OrderCannotBeFilled();

        uint256 currentTime = block.timestamp;
        if (currentTime > order.deadline) revert OrderExpired();

        address filler = Strings.parseAddress(order.filler);
        if (filler != address(0) && currentTime <= order.primaryFillerDeadline && filler != msg.sender) {
            revert RestrictedToPrimaryFiller();
        }

        emit OrderFillInitiated(orderId, msg.sender);

        bytes memory payload = abi.encode(order, orderNonce, fundingWallet, maxGas);
        return _lzSend(order.destinationChainEid, payload, "", MessagingFee(msg.value, 0), payable(msg.sender));
    }

    function withdrawOrder(Order memory order, uint256 orderNonce) external nonReentrant {
        address user = Strings.parseAddress(order.user);
        bytes32 orderId = getOrderId(order, orderNonce);
        if (order.deadline + timeBuffer > block.timestamp || orders[orderId] != Status.ACTIVE) {
            revert OrderCannotBeWithdrawn();
        }

        orders[orderId] = Status.WITHDRAWN;

        // transfer input assets back to the user
        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = Strings.parseAddress(input.tokenAddress);
            _transfer(input.tokenType, address(this), user, tokenAddress, input.tokenId, input.amount);
        }

        emit OrderWithdrawn(orderId, user);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        emit ERC721Received(operator, from, tokenId, data);
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        emit ERC1155Received(operator, from, id, value, data);
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override returns (bytes4) {
        emit ERC1155BatchReceived(operator, from, ids, values, data);
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721Receiver).interfaceId
            || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    /// @notice receive order settlement message from the executor contract
    function _lzReceive(Origin calldata, bytes32, bytes calldata payload, address, bytes calldata)
        internal
        override
        nonReentrant
    {
        (Order memory order, uint256 orderNonce, string memory fundingWalletStr) =
            abi.decode(payload, (Order, uint256, string));

        /**
         * address sender = Strings.parseAddress(message.sender);
         *     if (executors[message.sourceChainSelector] != sender) {
         *         revert InvalidSender();
         *     }
         *
         *     if (
         *         order.sourceChainSelector != message.destinationChainSelector
         *             || order.destinationChainSelector != message.sourceChainSelector
         *             || message.destinationChainSelector != block.chainid
         *     ) revert UnprocessableOrder();
         */
        bytes32 orderId = getOrderId(order, orderNonce);
        if (orders[orderId] != Status.ACTIVE) revert OrderCannotBeFilled();
        orders[orderId] = Status.FILLED;

        address fundingWallet = Strings.parseAddress(fundingWalletStr);

        for (uint256 i = 0; i < order.inputs.length; i++) {
            Token memory input = order.inputs[i];

            address tokenAddress = Strings.parseAddress(input.tokenAddress);
            _transfer(input.tokenType, address(this), fundingWallet, tokenAddress, input.tokenId, input.amount);
        }

        emit OrderFilled(orderId);
    }

    function _checkOrderValidity(Order memory order, bytes[] memory permits, bytes memory signature) internal view {
        if (order.inputs.length != permits.length) revert InvalidOrderInputApprovals();
        if (order.deadline > block.timestamp + maxOrderDeadline) revert InvalidDeadline();
        if (!validateOrder(order, signature)) revert InvalidOrderSignature();
        if (spokes[order.destinationChainEid] == address(0)) revert UnsupportedChain();
        if (order.primaryFillerDeadline > order.deadline) revert OrderDeadlinesMismatch();
        if (block.timestamp >= order.deadline) revert OrderExpired();
        if (order.sourceChainEid != block.chainid) revert InvalidSourceChain();
        if (block.timestamp >= order.primaryFillerDeadline) revert OrderPrimaryFillerExpired();
    }

    function _applyPermits(bytes memory permit, address user, address token) internal {
        // Decode the permit signature and call permit on the token
        (uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(permit, (uint256, uint256, uint8, bytes32, bytes32));

        PermitHelper.trustlessPermit(token, user, address(this), value, deadline, v, r, s);
    }
}
