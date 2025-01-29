// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

library BytesUtils {
    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function bytes32ToAddress(bytes32 _bytes) public pure returns (address) {
        return address(uint160(uint256(_bytes)));
    }
}
