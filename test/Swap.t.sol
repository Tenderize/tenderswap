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

import { TenderSwap, Config, BASE_FEE, _encodeTokenId, _decodeTokenId, FeeParams } from "@tenderize/swap/Swap.sol";
import { LPToken } from "@tenderize/swap/LPToken.sol";

import { UD60x18, ud, unwrap, ZERO, UNIT, wrap } from "@prb/math/UD60x18.sol";


contract FeeCalculatorHarness is TenderSwap {


    constructor(Config memory config) TenderSwap(config) {}

    function fee_test(uint256 x, uint256 u, uint256 s, uint256 U, uint256 S, uint256 L, uint256 k) external returns (uint256 response) {
        FeeParams memory params = FeeParams(
            wrap(x * 1e18),
            wrap(u * 1e18),
            wrap(s * 1e18),
            wrap(U * 1e18),
            wrap(S * 1e18),
            wrap(L * 1e18),
            wrap(k * 1e18)
        );

        response = unwrap(super._calcFee(params));
    }
}

contract TenderSwapTest is Test {
    MockERC20 underlying;
    MockERC20 tToken0;
    MockERC20 tToken1;

    TenderSwap swap;
    FeeCalculatorHarness feeSwap;

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
        vm.mockCall(registry, abi.encodeWithSelector(Registry.isTenderizer.selector), abi.encode(true));
        vm.mockCall(
            address(tToken0), abi.encodeWithSelector(TenderizerImmutableArgs.asset.selector), abi.encode(address(underlying))
        );
        vm.mockCall(
            address(tToken1), abi.encodeWithSelector(TenderizerImmutableArgs.asset.selector), abi.encode(address(underlying))
        );

        Config memory cfg = Config({ underlying: underlying, registry: registry, unlocks: unlocks });
        swap = new TenderSwap(cfg);
        feeSwap = new FeeCalculatorHarness(cfg);
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
        assertEq(swap.liabilities(), deposit1 + deposit2, "TenderSwap liquidity");
        assertEq(swap.liquidity(), deposit1 + deposit2, "TenderSwap available liquidity");
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
        assertEq(swap.liquidity(), 90 ether, "TenderSwap available liquidity");
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
        assertEq(swap.liquidity(), liquidity - amount, "TenderSwap available liquidity");
    }

    function testZeroSwap() public {
        // Zero test, first with only one token, then two token

        // Case 1 tToken, no unlocks
        uint256 liquidity = 100 ether;

        underlying.mint(address(this), liquidity);
        underlying.approve(address(swap), liquidity);
        swap.deposit(liquidity);

        uint256 amount = 0 ether;
        uint256 tokenId = _encodeTokenId(address(tToken0), 0);

        vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlock.selector, amount), abi.encode(0));
        vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlockMaturity.selector, 0), abi.encode(block.number + 100));

        tToken0.mint(address(this), 100 ether);
        tToken0.approve(address(swap), 10 ether);
        (uint256 out, uint256 fee) = swap.swap(address(tToken0), 0 ether, 0 ether);

        assertEq(out, 0, "No amount goes out");
        assertEq(fee, 0, "No fee paid");
        assertEq(swap.liquidity(), 100 ether, "No amount unlocked");

        // Add second token to check no errors happen here
        uint256 liquidity2 = 200 ether;
        underlying.mint(address(this), liquidity2);
        underlying.approve(address(swap), liquidity2);
        swap.deposit(liquidity2);
        
        // Sanity check to see whether deposit worked correctly
        assertEq(swap.liquidity(), 300 ether, "Second deposit succesful!");

        vm.mockCall(address(tToken1), abi.encodeWithSelector(Tenderizer.unlock.selector, amount), abi.encode(0));
        vm.mockCall(address(tToken1), abi.encodeWithSelector(Tenderizer.unlockMaturity.selector, 0), abi.encode(block.number + 100));

        tToken1.mint(address(this), 200 ether);
        tToken1.approve(address(swap), 200 ether);

        (uint256 out2, uint256 fee2) = swap.swap(address(tToken1), 0 ether, 0 ether);

        assertEq(out2, 0 ether, "No amount goes it in multiple token case");
        assertEq(fee2, 0 ether, "No fee in multiple token case");
        assertEq(swap.liquidity(), 300 ether, "No amount unlocked in multiple token case");
    }

    // Test to check for every variable for consistency
    function testUniqueTokenSwap() public {
        // Case U < u * (2 + k) is not possible with one token
        // Case U >= u * (2 + k) + (1 + k) * x only possible when x = 0
        uint256 response = feeSwap.fee_test(0, 0, 100, 0, 100, 1000, 3);
        assertEq(response, 0, "Case U >= u * (2 + k) + (1 + k) * x");
        
        // Case else

        // Case x = 0..100..20, u = 200, s = 100, U = 200, S = 100, L = 1000, k = 3, this is done with Maple
        uint256[6] memory responses;
        responses[0] = 0;
        responses[1] = 39072640000000000;
        responses[2] = 95252480000000000;
        responses[3] = 173627520000000000;
        responses[4] = 280207360000000000;
        responses[5] = 422000000000000000;

        for (uint256 i = 0; i < 6; i++) {
            uint256 x = i * 20;
            assertTrue(around(feeSwap.fee_test(x, 200, 100, 200, 100, 1000, 3), responses[i], 3));
        }

        // Case x = 100, u = 200, s = 100..600..100, U = 200, S = s, L = 1000, k = 3, tested with maple
        for (uint256 i = 100; i < 600; i = i + 100) {
            assertTrue(around(feeSwap.fee_test(100, 200, i, 200, i, 1000, 3), 422000000000000000, 1000));
        }

        // Case x = 100, u = 0..1000..200, s = 200, U = u, S = s, L = 1000, k = 3, tested with maple
        responses[0] = 2000000000000000;
        responses[1] = 422000000000000000;
        responses[2] = 4202000000000000000;
        responses[3] = 18062000000000000000;
        responses[4] = 52562000000000000000;
        responses[5] = 122102000000000000000;

        for (uint256 i = 0; i < 6; i++) {
            uint256 u = i * 200;
            assertTrue(around(feeSwap.fee_test(100, u, 200, u, 200, 1000, 3), responses[i], 1000));
        }

        // Case x = 100, u = 100, s = 200, U = u, S = s, L = 1..10001..200, k = 3, tested with maple
        responses[0] = 62000000000000000000000000000;
        responses[1] = 37984591465925498575;
        responses[2] = 2397806864000000000;
        responses[3] = 475219005900000000;
        responses[4] = 150612710800000000;
        responses[5] = 61752618760000000;

        for (uint256 i = 0; i < 2; i++) {
            uint256 L = 1 + i * 200;
            uint256 resp = feeSwap.fee_test(100, 100, 200, 100, 200, L, 3);
            assertTrue(around(resp, responses[i], 1000));
        }

        responses[0] = 2333333333333333333;
        responses[1] = 375000000000000000;
        responses[2] = 62000000000000000;
        responses[3] = 10500000000000000;
        responses[4] = 1814285714285714;
        responses[5] = 318750000000000;

        for (uint256 i = 0; i < 5; i++) {
            uint256 resp = feeSwap.fee_test(100, 100, 200, 100, 200, 1000, i + 1);
            assertTrue(around(resp, responses[i], 1000));
        }

    }

    // Test used to check two other branches
    function testMultipleTokenSwap() public {
        // Case U < u * (2 + k)

        // Case x = 50, u = 100, U = 150, s = 60, S = 100, L = 200, k = 5
        uint256 resp = feeSwap.fee_test(50, 100, 150, 60, 100, 200, 5);
        assertTrue(around(resp, 389382738095238095, 1000));

        // Case x = 0, u = 100, U = 150, s = 60, S = 100, L = 200, k = 5
        resp = feeSwap.fee_test(0, 100, 150, 60, 100, 200, 5);
        assertTrue(around(resp, 0, 1));

        // Case U >= u * (2 + k) + (1 + k) * x and x =/= 0

        resp = feeSwap.fee_test(100, 200, 1000, 100000, 200000, 1000000, 3);
        assertTrue(around(resp, 6260006876750000, 1000));

        // Few more general cases.

        // Case x = 60, u = 0, U = 1000, s = 60, S = 200, L = 300, k = 1
        resp = feeSwap.fee_test(60, 0, 1000, 60, 200, 300, 1);
        assertTrue(around(resp, 520000000000000000, 1000));

        // Case x = 60, u = 0, U = 0, s = 60, S = 100, L = 500, k = 15
        resp = feeSwap.fee_test(60, 0, 60, 0, 100, 500, 15);
        assertTrue(around(resp, 10875, 1000));

        // Case x = 100, u = 0, U = 200, s = 100, S = 100, L = 500, k = 2
        resp = feeSwap.fee_test(100, 0, 100, 200, 100, 500, 2);
        assertTrue(around(resp, 8600000000000000000, 1000));

        // Case x = 100, u = 200, U = 200, s = 100, S = 1000, L = 1000, k = 4
        resp = feeSwap.fee_test(100, 200, 100, 200, 1000, 1000, 4);
        assertTrue(around(resp, 443333333333333333, 10000));
    }

    function testAroundSanity() public {
        assertTrue(around(2, 0, 2));
        assertFalse(around(2, 0, 1));
        assertTrue(around(2, 4, 2));
        assertFalse(around(2, 4, 1));
    }

    // Helper function to 
    function around(uint256 expected, uint256 value, uint256 epsilon) internal pure returns (bool resp) {
        expected > value ? resp = (expected - value <= epsilon) : resp = (value - expected <= epsilon);
    }
}
