// SPDX-License-Identifier: MIT
//
//  _____              _           _
// |_   _|            | |         (_)
//   | | ___ _ __   __| | ___ _ __ _ _______
//   | |/ _ \ '_ \ / _` |/ _ \ '__| |_  / _ \
//   | |  __/ | | | (_| |  __/ |  | |/ /  __/
//   \_/\___|_| |_|\__,_|\___|_|  |_/___\___|
//
// Copyright (c) Tenderize Labs Ltd

pragma solidity >=0.8.19;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "test/helpers/MockERC20.sol";
import { Registry } from "@tenderize/stake/registry/Registry.sol";
import { Tenderizer, TenderizerImmutableArgs } from "@tenderize/stake/tenderizer/Tenderizer.sol";

import { TenderSwap, Config, BASE_FEE, _encodeTokenId, _decodeTokenId } from "@tenderize/swap/Swap.sol";
import { LPToken } from "@tenderize/swap/LPToken.sol";

import { UD60x18, ud, unwrap, ZERO, UNIT } from "@prb/math/UD60x18.sol";

contract TenderSwapTest is Test {
    MockERC20 underlying;
    MockERC20 tToken0;
    MockERC20 tToken1;

    TenderSwap swap;

    address registry;
    address unlocks;

    address addr1;
    address addr2;

    function setUp() public {
        underlying = new MockERC20("network.xyz", "XYZ", 18);
        tToken0 = new MockERC20("tXYZ_0x00", "tXYZ_0x00", 18);
        tToken1 = new MockERC20("tXYZ_0x01", "tXYZ_0x00", 18);

        registry = vm.addr(123);
        unlocks = vm.addr(567);

        addr1 = vm.addr(111);
        addr2 = vm.addr(222);

        // default mock calls
        vm.mockCall(registry, abi.encodeWithSelector(Registry.isTenderizer.selector), abi.encode(true));
        vm.mockCall(
            address(tToken0), abi.encodeWithSelector(TenderizerImmutableArgs.asset.selector), abi.encode(address(underlying))
        );
        vm.mockCall(
            address(tToken1), abi.encodeWithSelector(TenderizerImmutableArgs.asset.selector), abi.encode(address(underlying))
        );

        Config memory cfg = Config({ underlying: underlying, registry: registry, unlocks: unlocks });
        swap = new TenderSwap(cfg);
    }

    function test_deposits() public {
        uint256 deposit1 = 100 ether;
        uint256 deposit2 = 250 ether;
        underlying.mint(addr1, deposit1);
        underlying.mint(addr2, deposit2);

        vm.startPrank(addr1);
        underlying.approve(address(swap), deposit1);
        swap.deposit(deposit1);
        vm.stopPrank();

        vm.startPrank(addr2);
        underlying.approve(address(swap), deposit2);
        swap.deposit(deposit2);
        vm.stopPrank();

        assertEq(swap.lpToken().totalSupply(), deposit1 + deposit2, "lpToken totalSupply");
        assertEq(swap.lpToken().balanceOf(addr1), deposit1, "addr1 lpToken balance");
        assertEq(swap.lpToken().balanceOf(addr2), deposit2, "addr2 lpToken balance");
        assertEq(underlying.balanceOf(address(swap)), deposit1 + deposit2, "TenderSwap underlying balance");
        assertEq(swap.liquidity(), deposit1 + deposit2, "TenderSwap liquidity");
        assertEq(swap.availableLiquidity(), deposit1 + deposit2, "TenderSwap available liquidity");
        assertTrue(swap.utilisation().eq(ZERO), "TenderSwap utilisation");
        assertTrue(swap.utilisationFee().eq(BASE_FEE), "TenderSwap utilisation fee");
    }

    function test_swap() public {
        uint256 liquidity = 100 ether;
        underlying.mint(address(this), liquidity);
        underlying.approve(address(swap), liquidity);
        swap.deposit(liquidity);

        uint256 amount = 10 ether;
        uint256 tokenId = _encodeTokenId(address(tToken0), 0);

        vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlock.selector, amount), abi.encode(0));
        vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlockMaturity.selector, 0), abi.encode(block.number + 100));

        tToken0.mint(address(this), 100 ether);
        tToken0.approve(address(swap), 10 ether);
        (uint256 out, uint256 fee) = swap.swap(address(tToken0), 10 ether, 5 ether);

        // Fee should be 0.15% or 0.0015
        // As utilisation after is 0.1 and 0.1^3 = 0.001
        // Base fee is 0.005 so that makes 0.0015
        // Since there is only 1 token drawing liquidity, its weight is 1
        uint256 expFee = amount * 15 / 10_000;

        assertEq(fee, expFee, "swap fee");
        assertEq(out, amount - expFee, "swap out");
        assertEq(swap.availableLiquidity(), 90 ether, "TenderSwap available liquidity");
    }

    function testFuzz_swap(uint256 liquidity, uint256 amount) public {
        liquidity = bound(liquidity, 1e18, type(uint64).max);
        amount = bound(amount, 1e9, liquidity);

        underlying.mint(address(this), liquidity);
        underlying.approve(address(swap), liquidity);
        swap.deposit(liquidity);

        vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlock.selector, amount), abi.encode(0));
        vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlockMaturity.selector, 0), abi.encode(block.number + 100));

        tToken0.mint(address(this), liquidity);
        tToken0.approve(address(swap), amount);
        (uint256 out, uint256 fee) = swap.swap(address(tToken0), amount, 0);

        uint256 expFee = unwrap(ud(amount).mul((BASE_FEE + ud(amount).div(ud(liquidity)).pow(ud(3e18)))));
        expFee = expFee >= amount ? amount : expFee;

        assertEq(fee, expFee, "swap fee");
        assertEq(out, amount - expFee, "swap out");
        assertEq(swap.availableLiquidity(), liquidity - amount, "TenderSwap available liquidity");
    }
}
