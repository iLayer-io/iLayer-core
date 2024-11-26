// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {bytes64} from "@equito-network/libraries/EquitoMessageLibrary.sol";

interface IEquitoRouter {
    function getFee(address sender) external view returns (uint256);

    function sendMessage(bytes64 calldata receiver, uint256 destinationChainSelector, bytes calldata data)
        external
        payable
        returns (bytes32);
}
