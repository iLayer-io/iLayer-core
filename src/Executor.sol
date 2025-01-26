// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ExcessivelySafeCall} from "@safecall/ExcessivelySafeCall.sol";

/**
 * @title Executor contract
 * @dev Helper to execute arbitrary contract calls
 * @custom:security-contact security@ilayer.io
 */
contract Executor {
    using ExcessivelySafeCall for address;

    event ContractCallExecuted(address target);

    function exec(address target, uint256 gas, uint256 value, uint16 maxCopy, bytes memory data)
        external
        returns (bool)
    {
        (bool res,) = target.excessivelySafeCall(gas, value, maxCopy, data);

        emit ContractCallExecuted(target);

        return res;
    }
}
