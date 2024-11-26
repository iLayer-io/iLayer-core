// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import "../src/libraries/TransferUtils.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract MockERC721 is ERC721 {
    constructor() ERC721("MockERC721", "M721") {
        _mint(msg.sender, 1);
    }
}

contract MockERC1155 is ERC1155 {
    constructor() ERC1155("https://api.example.com") {
        _mint(msg.sender, 1, 1000, "");
    }
}

contract User is ERC721Holder, ERC1155Holder {
    constructor() ERC1155Holder() {}
}

contract TransferUtilsTest is Test {
    MockERC721 private immutable erc721;
    MockERC1155 private immutable erc1155;
    address private immutable from;
    address private immutable to;

    constructor() {
        erc721 = new MockERC721();
        erc1155 = new MockERC1155();
        from = address(new User());
        to = address(new User());
    }

    function testIsERC721() public {
        assertTrue(TransferUtils.isERC721(address(erc721)));
    }

    function testIsERC1155() public {
        assertTrue(TransferUtils.isERC1155(address(erc1155)));
    }

    function testSupportsInterfaceERC721() public {
        assertTrue(TransferUtils.supportsInterface(address(erc721), type(IERC721).interfaceId));
    }

    function testSupportsInterfaceERC1155() public {
        assertTrue(TransferUtils.supportsInterface(address(erc1155), type(IERC1155).interfaceId));
    }

    function testTransferERC721() public {
        erc721.approve(from, 1);
        TransferUtils.transfer(from, to, address(erc721), 1, 0);
        assertEq(erc721.ownerOf(1), to);
    }

    function testTransferERC1155() public {
        erc1155.setApprovalForAll(from, true);
        TransferUtils.transfer(from, to, address(erc1155), 1, 100);
        assertEq(erc1155.balanceOf(to, 1), 100);
    }
}
