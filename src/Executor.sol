// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ExcessivelySafeCall} from "@safecall/ExcessivelySafeCall.sol";

contract Executor {
    using ExcessivelySafeCall for address;

    address public immutable owner;

    event CallExecuted(address target);

    error OnlyOwner();

    constructor() {
        owner = msg.sender;
    }

    function exec(address target, uint256 gas, uint256 value, uint16 maxCopy, bytes memory data)
        external
        returns (bool)
    {
        if (msg.sender != owner) revert OnlyOwner();

        (bool res,) = target.excessivelySafeCall(gas, value, maxCopy, data);

        emit CallExecuted(target);

        return res;
    }
}
