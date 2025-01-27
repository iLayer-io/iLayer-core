// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {OrderSpoke} from "../src/OrderSpoke.sol";

contract DeployScript is Script {
    uint32 private aEid = 1;
    uint32 private bEid = 2;

    OrderHub public hub;
    OrderSpoke public spoke;
    address public router;

    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function run() external {
        hub = new OrderHub(router);
        spoke = new OrderSpoke(router);

        hub.setPeer(bEid, addressToBytes32(address(spoke)));
        spoke.setPeer(aEid, addressToBytes32(address(hub)));
    }
}
