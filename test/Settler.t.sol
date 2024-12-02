// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {bytes64, EquitoMessage, EquitoMessageLibrary} from "@equito-network/libraries/EquitoMessageLibrary.sol";
import {Validator} from "../src/Validator.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {Settler} from "../src/Settler.sol";
import {BaseTest} from "./BaseTest.sol";

contract SettlerTest is BaseTest {
    constructor() BaseTest() {}

    function setUp() public {
        uint256[] memory chainSelectors = new uint256[](1);
        chainSelectors[0] = block.chainid;
        bytes64[] memory addresses = new bytes64[](1);
        addresses[0] = EquitoMessageLibrary.addressToBytes64(address(settler));
        orderbook.setPeers(chainSelectors, addresses);

        settler.setOrderbook(block.chainid, address(orderbook));
    }

    function testFillOrder(uint256 inputAmount, uint256 outputAmount) public {
        vm.assume(inputAmount > 0);

        address filler = user1;

        Validator.Order memory order = buildOrder(
            filler,
            inputAmount,
            outputAmount,
            user0,
            user0_pk,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes
        );

        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        inputToken.approve(address(orderbook), inputAmount);
        orderbook.createOrder(order);

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(settler), outputAmount);
        settler.fillOrder(order);
        vm.stopPrank();

        validateOrderWasFilled(user0, filler, inputAmount, outputAmount);
    }

    function testFillOrderEmptyFiller() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 1e18;

        Validator.Order memory order = buildOrder(
            address(0),
            inputAmount,
            outputAmount,
            user0,
            user0_pk,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes
        );

        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        inputToken.approve(address(orderbook), inputAmount);
        orderbook.createOrder(order);

        address filler = user1;

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(settler), outputAmount);
        settler.fillOrder(order);
        vm.stopPrank();

        validateOrderWasFilled(user0, filler, inputAmount, outputAmount);
    }
}
