// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

library TransferUtils {
    bytes4 private constant ERC721_INTERFACE_ID = 0x80ac58cd;
    bytes4 private constant ERC1155_INTERFACE_ID = 0xd9b67a26;

    error UnsupportedTransfer();

    function isERC721(address tokenAddress) internal view returns (bool) {
        return supportsInterface(tokenAddress, ERC721_INTERFACE_ID);
    }

    function isERC1155(address tokenAddress) internal view returns (bool) {
        return supportsInterface(tokenAddress, ERC1155_INTERFACE_ID);
    }

    function supportsInterface(address tokenAddress, bytes4 interfaceId) internal view returns (bool) {
        (bool success, bytes memory result) = tokenAddress.staticcall(
            abi.encodeWithSelector(0x01ffc9a7, interfaceId) // ERC165 supportsInterface selector
        );
        return (success && result.length == 32 && abi.decode(result, (bool)));
    }

    function transfer(address from, address to, address token, uint256 id, uint256 amount) external {
        if (isERC721(token)) {
            IERC721(token).safeTransferFrom(from, to, id);
        } else if (isERC1155(token)) {
            IERC1155(token).safeTransferFrom(from, to, id, amount, "");
        } else {
            revert UnsupportedTransfer();
        }
    }
}
