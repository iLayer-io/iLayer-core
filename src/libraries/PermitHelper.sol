// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev taken from https://github.com/trust1995/trustlessPermit
library PermitHelper {
    error PermitFailure();

    function trustlessPermit(
        address token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        // Try permit() before allowance check to advance nonce if possible
        try IERC20Permit(token).permit(owner, spender, value, deadline, v, r, s) {
            return;
        } catch {
            // Permit potentially got frontran. Continue anyways if allowance is sufficient.
            if (IERC20(token).allowance(owner, spender) >= value) {
                return;
            }
        }

        revert PermitFailure();
    }
}
