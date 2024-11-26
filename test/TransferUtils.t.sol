// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import "../src/libraries/TransferUtils.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract MockERC721 is ERC721 {
    constructor() ERC721("test", "TEST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockERC1155 is ERC1155 {
    constructor() ERC1155("TEST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, 0, amount, "");
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

    function testBase() public view {
        assertTrue(TransferUtils.isERC721(address(erc721)));
        assertTrue(TransferUtils.isERC1155(address(erc1155)));
        assertTrue(TransferUtils.supportsInterface(address(erc721), type(IERC721).interfaceId));
        assertTrue(TransferUtils.supportsInterface(address(erc1155), type(IERC1155).interfaceId));
    }

    function testTransferERC721() public {
        erc721.mint(from, 1);

        vm.prank(from);
        erc721.approve(address(this), 1);

        assertEq(erc721.ownerOf(1), from);
        TransferUtils.transfer(from, to, address(erc721), 1, 0);
        assertEq(erc721.ownerOf(1), to);
    }

    function testTransferERC1155() public {
        erc1155.mint(from, 1);

        vm.prank(from);
        erc1155.setApprovalForAll(address(this), true);

        assertEq(erc1155.balanceOf(to, 0), 0);
        TransferUtils.transfer(from, to, address(erc1155), 0, 1);
        assertEq(erc1155.balanceOf(to, 0), 1);
    }
}
