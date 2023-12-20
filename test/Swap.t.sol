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

import { Test, console } from "forge-std/Test.sol";
import { ERC721 } from "solmate/tokens/ERC721.sol";
import { MockERC20 } from "test/helpers/MockERC20.sol";

import { Adapter } from "@tenderize/stake/adapters/Adapter.sol";
import { Registry } from "@tenderize/stake/registry/Registry.sol";
import { Tenderizer, TenderizerImmutableArgs } from "@tenderize/stake/tenderizer/Tenderizer.sol";

import { TenderSwap, Config, BASE_FEE, RELAYER_CUT, MIN_LP_CUT, _encodeTokenId, _decodeTokenId } from "@tenderize/swap/Swap.sol";
import { LPToken } from "@tenderize/swap/LPToken.sol";

import { SD59x18, ZERO, UNIT, unwrap, sd } from "@prb/math/SD59x18.sol";
import { UD60x18, ud, UNIT as UNIT_60x18 } from "@prb/math/ud60x18.sol";

import { SwapHarness } from "./Swap.harness.sol";
import { UnlockQueue } from "@tenderize/swap/UnlockQueue.sol";

import { acceptableDelta } from "./helpers/Utils.sol";

contract TenderSwapTest is Test {
    MockERC20 underlying;
    MockERC20 tToken0;
    MockERC20 tToken1;

    SwapHarness swap;

    address registry;
    address unlocks;
    address adapter;

    address addr1;
    address addr2;

    event RelayerRewardsClaimed(address indexed relayer, uint256 rewards);

    function setUp() public {
        underlying = new MockERC20("network.xyz", "XYZ", 18);
        tToken0 = new MockERC20("tXYZ_0x00", "tXYZ_0x00", 18);
        tToken1 = new MockERC20("tXYZ_0x01", "tXYZ_0x00", 18);

        registry = vm.addr(123);
        unlocks = vm.addr(567);
        adapter = vm.addr(789);

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
        swap = new SwapHarness(cfg);
    }

    function testFuzz_deposits(uint256 x, uint256 y, uint256 l) public {
        uint256 deposit1 = bound(x, 1, type(uint128).max);
        uint256 deposit2 = bound(y, 1, type(uint128).max);
        l = bound(l, 1, type(uint128).max);
        underlying.mint(addr1, deposit1);
        underlying.mint(addr2, deposit2);

        vm.startPrank(addr1);
        underlying.approve(address(swap), deposit1);
        swap.deposit(deposit1);
        vm.stopPrank();

        // Change liabilities !
        swap.exposed_setLiabilities(l);

        vm.startPrank(addr2);
        underlying.approve(address(swap), deposit2);
        swap.deposit(deposit2);
        vm.stopPrank();

        uint256 expBalY = deposit2 * deposit1 / l;

        assertEq(swap.lpToken().totalSupply(), deposit1 + expBalY, "lpToken totalSupply");
        assertEq(swap.lpToken().balanceOf(addr1), deposit1, "addr1 lpToken balance");
        assertEq(swap.lpToken().balanceOf(addr2), expBalY, "addr2 lpToken balance");
        assertEq(underlying.balanceOf(address(swap)), deposit1 + deposit2, "TenderSwap underlying balance");
    }

    function test_claimRelayerRewards(uint256 amount) public {
        amount = 10 ether;
        swap.exposed_setRelayerRewards(amount, addr1);
        underlying.mint(address(swap), amount);
        assertEq(swap.pendingRelayerRewards(addr1), amount, "pending rewards");
        vm.expectEmit(true, true, true, true);
        emit RelayerRewardsClaimed(addr1, amount);

        vm.prank(addr1);
        swap.claimRelayerRewards();
        assertEq(swap.pendingRelayerRewards(addr1), 0, "pending rewards");
        assertEq(underlying.balanceOf(addr1), amount, "addr1 balance");
    }

    // write end to end swap test with checking the queue
    // make three swaps, check the queue state (check head and tail)
    // buy up the last unlock and check all code paths
    // * mock unlocks as ERC721 mock transfer
    // process blocks and redeem the first unlock and check all code paths
    // * mock Tenderizer.withdraw()
    // check that queue is now only containing the second unlock
    // * Mock Tenderizer.unlock() and Tenderizer.unlockMaturity()

    function test_scenario_full() public {
        uint256 unlockTime = 100;
        tToken0.mint(address(this), 10_000 ether);
        tToken0.approve(address(swap), 10_000 ether);

        // 1. Deposit Liquidity
        uint256 liquidity = 100 ether;
        underlying.mint(address(this), liquidity);
        underlying.approve(address(swap), liquidity);
        swap.deposit(liquidity);

        vm.mockCall(address(tToken0), abi.encodeWithSelector(TenderizerImmutableArgs.adapter.selector), abi.encode(adapter));

        // 2. Make 3 swaps
        uint256 amount = 10 ether;
        vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlock.selector, amount), abi.encode(1));
        vm.mockCall(
            address(tToken0), abi.encodeWithSelector(Tenderizer.unlockMaturity.selector, 1), abi.encode(block.number + unlockTime)
        );
        swap.swap(address(tToken0), 10 ether, 0 ether);

        uint256 unlockBlockOne = block.number;
        uint256 unlockBlockTwo = block.number + 1;
        uint256 unlockBlockThree = block.number + 2;

        vm.roll(unlockBlockTwo);
        amount = 20 ether;
        vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlock.selector, amount), abi.encode(2));
        vm.mockCall(
            address(tToken0), abi.encodeWithSelector(Tenderizer.unlockMaturity.selector, 2), abi.encode(block.number + unlockTime)
        );
        swap.swap(address(tToken0), 20 ether, 0 ether);

        vm.roll(unlockBlockThree);
        amount = 30 ether;
        vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlock.selector, amount), abi.encode(3));
        vm.mockCall(
            address(tToken0), abi.encodeWithSelector(Tenderizer.unlockMaturity.selector, 3), abi.encode(block.number + unlockTime)
        );
        swap.swap(address(tToken0), 30 ether, 0 ether);

        // 3. Check queue state
        UnlockQueue.Item memory head = swap.oldestUnlock();
        assertEq(head.id, _encodeTokenId(address(tToken0), 1), "head id");
        assertEq(head.amount, 10 ether, "head amount");
        assertEq(head.maturity, unlockBlockOne + unlockTime, "head maturity");

        UnlockQueue.Node memory middleUnlock = swap.exposed_queueQuery(_encodeTokenId(address(tToken0), 2));
        assertEq(middleUnlock.prev, _encodeTokenId(address(tToken0), 1), "middleUnlock prev");
        assertEq(middleUnlock.next, _encodeTokenId(address(tToken0), 3), "middleUnlock next");
        assertEq(middleUnlock.data.id, _encodeTokenId(address(tToken0), 2), "middleUnlock id");
        assertEq(middleUnlock.data.amount, 20 ether, "middleUnlock amount");
        assertEq(middleUnlock.data.maturity, unlockBlockTwo + unlockTime, "middleUnlock maturity");

        UnlockQueue.Item memory tail = swap.newestUnlock();
        assertEq(tail.id, _encodeTokenId(address(tToken0), 3), "tail id");
        assertEq(tail.amount, 30 ether, "tail amount");
        assertEq(tail.maturity, unlockBlockThree + unlockTime, "tail maturity");

        // 4. Buy up the last unlock
        uint256 currentTime = unlockBlockThree + 50;
        vm.mockCall(adapter, abi.encodeWithSelector(Adapter.currentTime.selector), abi.encode(currentTime));
        vm.mockCall(adapter, abi.encodeWithSelector(Adapter.unlockTime.selector), abi.encode(unlockTime));

        vm.mockCall(
            unlocks,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256)", address(swap), address(this), _encodeTokenId(address(tToken0), 3)
            ),
            abi.encode(true)
        );
        underlying.mint(address(this), 30 ether);
        underlying.approve(address(swap), 30 ether);
        // console.log("fee %s", tail.fee);
        // console.log("lp cut %s", uint256(unwrap(sd(int256(uint256(tail.fee))).mul(sd(0.1e18)))));
        // console.log("maturity %s", tail.maturity);
        // console.log("block num %s", block.number);

        uint256 liabilitiesBefore = swap.liabilities();
        {
            // buy unlock 3
            assertEq(swap.buyUnlock(), _encodeTokenId(address(tToken0), 3), "bought id");
            UD60x18 tailFee = ud(tail.fee);
            UD60x18 baseReward = tailFee.sub(tailFee.mul(MIN_LP_CUT));
            UD60x18 timeLeft = ud(tail.maturity - currentTime);
            UD60x18 unlockTimex18 = ud(unlockTime);
            UD60x18 progress = timeLeft.div(unlockTimex18);
            assertEq(swap.liabilities(), liabilitiesBefore + tailFee.sub(baseReward.mul(progress)).unwrap(), "liabilities");
            // sanity check that the LP cut is half of the baseReward plus the LP cut
            assertEq(
                swap.liabilities(), liabilitiesBefore + tailFee.sub(baseReward.div(ud(2e18))).unwrap(), "liabilities sanity check"
            );
        }
        assertEq(swap.exposed_unlocking(), 20 ether + 10 ether, "unlocking");
        assertEq(swap.exposed_unlockingForAsset(address(tToken0)), 20 ether + 10 ether, "unlocking for asset");
        head = swap.oldestUnlock();
        assertEq(head.id, _encodeTokenId(address(tToken0), 1), "head id");
        tail = swap.newestUnlock();
        assertEq(tail.id, _encodeTokenId(address(tToken0), 2), "tail id");

        // 5. Redeem the first unlock
        vm.roll(unlockBlockOne + unlockTime);
        vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.withdraw.selector, address(swap), 1), abi.encode(10 ether));
        liabilitiesBefore = swap.liabilities();
        swap.redeemUnlock();
        assertEq(swap.liabilities(), liabilitiesBefore + ud(head.fee).sub(ud(head.fee).mul(RELAYER_CUT)).unwrap(), "liabilities");
        assertEq(swap.pendingRelayerRewards(address(this)), ud(head.fee).mul(RELAYER_CUT).unwrap(), "relayer rewards");
        assertEq(swap.exposed_unlocking(), 20 ether, "unlocking"); // unlock 2 remains
        assertEq(swap.exposed_unlockingForAsset(address(tToken0)), 20 ether, "unlocking for asset"); // unlock 2 remains
        head = swap.oldestUnlock();
        assertEq(head.id, _encodeTokenId(address(tToken0), 2), "head id");
        tail = swap.newestUnlock();
        assertEq(tail.id, _encodeTokenId(address(tToken0), 2), "tail id");
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

        tToken0.mint(address(this), 10_000 ether);
        tToken0.approve(address(swap), 150 ether);
        (uint256 out, uint256 fee) = swap.swap(address(tToken0), 10 ether, 5 ether);

        uint256 expFee = amount * 75 / 100_000;

        assertEq(fee, expFee, "swap fee");
        assertEq(out, amount - expFee, "swap out");
        assertEq(swap.liquidity(), 90 ether, "TenderSwap available liquidity");
    }

    // function testFuzz_swap_other(
    //     uint256 liquidity,
    //     uint256 t0Supply,
    //     uint256 t1Supply,
    //     uint256 t0Amount,
    //     uint256 t1Amount
    // )
    //     public
    // {
    //     vm.assume(liquidity >= 10 ether && liquidity <= type(uint128).max);
    //     t0Supply = bound(t0Supply, 1 ether, liquidity);
    //     t1Supply = bound(t1Supply, 1 ether, liquidity);
    //     t0Amount = bound(t0Amount, 1 ether / 5, t0Supply / 5);
    //     t1Amount = bound(t1Amount, 1 ether / 5, t1Supply / 5);

    //     underlying.mint(address(this), liquidity);
    //     underlying.approve(address(swap), liquidity);
    //     swap.deposit(liquidity);

    //     uint256 tokenId = _encodeTokenId(address(tToken0), 0);

    //     vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlock.selector, t0Amount), abi.encode(0));
    //     vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlockMaturity.selector, 0), abi.encode(block.number +
    // 100));

    //     tToken0.mint(address(this), t0Amount);
    //     tToken1.mint(address(this), t1Amount);
    //     tToken0.approve(address(swap), t0Amount);
    //     (uint256 out, uint256 fee) = swap.swap(address(tToken0), t0Amount, 0 ether);

    //     (out, fee) = swap.quote(address(tToken1), t1Amount);
    //     console.log("swap quote 1", out, fee);
    //     // Fee should be 0.15% or 0.0015
    //     // As utilisation after is 0.1 and 0.1^3 = 0.001
    //     // Base fee is 0.005 so that makes 0.0015
    //     // Since there is only 1 token drawing liquidity, its weight is 1

    //     // uint256 expFee = amount * 15 / 10_000;

    //     // assertEq(fee, expFee, "swap fee");
    //     // assertEq(out, amount - expFee, "swap out");
    //     // assertEq(swap.liquidity(), 90 ether, "TenderSwap available liquidity");
    // }

    // function test_swap_other() public {
    //     uint256 liquidity = 2_000_000 ether;
    //     underlying.mint(address(this), liquidity);
    //     underlying.approve(address(swap), liquidity);
    //     swap.deposit(liquidity);

    //     uint256 amount = 1 ether;
    //     uint256 tokenId = _encodeTokenId(address(tToken0), 0);

    //     vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlock.selector, amount), abi.encode(0));
    //     vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlockMaturity.selector, 0), abi.encode(block.number +
    // 100));

    //     tToken0.mint(address(this), 34_000 ether);
    //     tToken1.mint(address(this), 14_000 ether);
    //     tToken0.approve(address(swap), 1500 ether);
    //     (uint256 out, uint256 fee) = swap.swap(address(tToken0), amount, 0 ether);

    //     (out, fee) = swap.quote(address(tToken1), 50 ether);
    //     console.log("swap quote 1", out, fee);
    //     // Fee should be 0.15% or 0.0015
    //     // As utilisation after is 0.1 and 0.1^3 = 0.001
    //     // Base fee is 0.005 so that makes 0.0015
    //     // Since there is only 1 token drawing liquidity, its weight is 1
    //     uint256 expFee = amount * 15 / 10_000;

    //     // assertEq(fee, expFee, "swap fee");
    //     // assertEq(out, amount - expFee, "swap out");
    //     // assertEq(swap.liquidity(), 90 ether, "TenderSwap available liquidity");
    // }

    // // function testFuzz_swap_basic(uint256 liquidity, uint256 amount) public {
    // //     liquidity = bound(liquidity, 1e18, type(uint128).max);
    // //     amount = bound(amount, 1e3, liquidity);

    // //     underlying.mint(address(this), liquidity);
    // //     underlying.approve(address(swap), liquidity);
    // //     swap.deposit(liquidity);

    // //     vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlock.selector, amount), abi.encode(0));
    // //     vm.mockCall(address(tToken0), abi.encodeWithSelector(Tenderizer.unlockMaturity.selector, 0), abi.encode(block.number +
    // // 100));

    // //     tToken0.mint(address(this), liquidity);
    // //     tToken0.approve(address(swap), amount);
    // //     (uint256 out, uint256 fee) = swap.swap(address(tToken0), amount, 0);

    // //     uint256 expFee = uint256(
    // //         sd(int256(amount)).mul(BASE_FEE).add(
    // //             sd(int256(amount)).mul((sd(int256(amount)).div(sd(int256(liquidity))).pow(sd(3e18))))
    // //         ).unwrap()
    // //     );
    // //     expFee = expFee >= amount ? amount : expFee;

    // //     console.log("expFee", expFee);
    // //     console.log("fee", fee);

    // //     assertTrue(acceptableDelta(fee, expFee, 2), "fee amount");
    // //     assertTrue(acceptableDelta(out, amount - expFee, 2), "swap out");
    // //     assertEq(swap.liquidity(), liquidity - amount, "TenderSwap available liquidity");
    // // }
}
