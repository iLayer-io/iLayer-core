// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

library TransferUtils {
    bytes4 private constant ERC721_INTERFACE_ID = type(IERC721).interfaceId;
    bytes4 private constant ERC1155_INTERFACE_ID = type(IERC1155).interfaceId;

    error UnsupportedTransfer();

    function isERC721(address tokenAddress) internal view returns (bool) {
        return supportsInterface(tokenAddress, ERC721_INTERFACE_ID);
    }

    function isERC1155(address tokenAddress) internal view returns (bool) {
        return supportsInterface(tokenAddress, ERC1155_INTERFACE_ID);
    }

    function supportsInterface(address tokenAddress, bytes4 interfaceId) internal view returns (bool) {
        (bool success, bytes memory result) = tokenAddress.staticcall(abi.encodeWithSelector(0x01ffc9a7, interfaceId));
        return (success && abi.decode(result, (bool)));
    }

    /**
     * @dev Transfers an ERC721 or ERC1155 token from one address to another.
     *      The function determines the token standard by checking supported interfaces.
     * @param from The address to transfer tokens from.
     * @param to The address to transfer tokens to.
     * @param token The address of the token contract.
     * @param id The ID of the token to transfer.
     * @param amount The amount of tokens to transfer (used for ERC1155).
     */
    function transfer(address from, address to, address token, uint256 id, uint256 amount) internal {
        if (isERC721(token)) {
            IERC721(token).safeTransferFrom(from, to, id);
        } else if (isERC1155(token)) {
            IERC1155(token).safeTransferFrom(from, to, id, amount, "");
        } else {
            revert UnsupportedTransfer();
        }
    }
}
