// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {BaseScript} from "./BaseScript.sol";

contract DeployScript is BaseScript {
    function run() external {
        vm.startBroadcast(userPrivateKey);

        deployContracts();

        vm.stopBroadcast();
    }
}
