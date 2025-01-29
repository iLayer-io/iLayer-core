// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {BytesUtils} from "../src/libraries/BytesUtils.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";

contract DeployScript is Script {
    uint32 private aEid = 1;
    uint32 private bEid = 2;

    OrderHub public hub;
    OrderSpoke public spoke;
    address public router;

    function run() external {
        hub = new OrderHub(router);
        spoke = new OrderSpoke(router);

        hub.setPeer(bEid, BytesUtils.addressToBytes32(address(spoke)));
        spoke.setPeer(aEid, BytesUtils.addressToBytes32(address(hub)));
    }
}
