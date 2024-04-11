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
import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { Adapter } from "@tenderize/stake/adapters/Adapter.sol";
import { Registry } from "@tenderize/stake/registry/Registry.sol";
import { Tenderizer, TenderizerImmutableArgs } from "@tenderize/stake/tenderizer/Tenderizer.sol";

import { TenderSwap, ConstructorConfig, _encodeTokenId, _decodeTokenId } from "@tenderize/swap/Swap.sol";
import { LPToken } from "@tenderize/swap/LPToken.sol";

import { SD59x18, ZERO, UNIT, unwrap, sd } from "@prb/math/SD59x18.sol";
import { UD60x18, ud, UNIT as UNIT_60x18 } from "@prb/math/UD60x18.sol";

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
    address treasury;
    address adapter;

    address addr1;
    address addr2;

    event RelayerRewardsClaimed(address indexed relayer, uint256 rewards);

    Registry private constant REGISTRY = Registry(0xa7cA8732Be369CaEaE8C230537Fc8EF82a3387EE);
    ERC721 private constant UNLOCKS = ERC721(0xb98c7e67f63d198BD96574073AD5B3427a835796);
    address private constant TREASURY = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    function setUp() public {
        underlying = new MockERC20("network.xyz", "XYZ", 18);
        tToken0 = new MockERC20("tXYZ_0x00", "tXYZ_0x00", 18);
        tToken1 = new MockERC20("tXYZ_0x01", "tXYZ_0x00", 18);

        registry = address(REGISTRY);
        unlocks = address(UNLOCKS);
        treasury = address(TREASURY);
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

        ConstructorConfig memory cfg = ConstructorConfig({ UNDERLYING: underlying, BASE_FEE: sd(0.0005e18), K: sd(3e18) });
        swap = new SwapHarness(cfg);
        address proxy = address(new ERC1967Proxy(address(swap), ""));
        swap = SwapHarness(proxy);
        swap.intialize();
    }

    function testFuzz_deposits(uint256 x, uint256 y, uint256 l) public {
        uint256 deposit1 = bound(x, 100, type(uint128).max);
        l = bound(l, deposit1, deposit1 * 1e18);
        uint256 deposit2 = bound(y, 100, type(uint128).max);
        underlying.mint(addr1, deposit1);
        underlying.mint(addr2, deposit2);

        vm.startPrank(addr1);
        underlying.approve(address(swap), deposit1);
        swap.deposit(deposit1, 0);
        vm.stopPrank();

        // Change liabilities !
        swap.exposed_setLiabilities(l);
        underlying.mint(address(swap), l - deposit1);

        vm.startPrank(addr2);
        underlying.approve(address(swap), deposit2);
        swap.deposit(deposit2, 0);
        vm.stopPrank();

        uint256 expBal2 = deposit2 * (deposit1 * 1e18 / l);

        assertEq(swap.lpToken().totalSupply(), (deposit1 * 1e18 + expBal2), "lpToken totalSupply");
        assertEq(swap.lpToken().balanceOf(addr1), deposit1 * 1e18, "addr1 lpToken balance");
        assertEq(swap.lpToken().balanceOf(addr2), expBal2, "addr2 lpToken balance");
        assertEq(underlying.balanceOf(address(swap)), l + deposit2, "TenderSwap underlying balance");
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
        swap.deposit(liquidity, 0);

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
        // buy unlock 3
        assertEq(swap.buyUnlock(), _encodeTokenId(address(tToken0), 3), "bought id");
        UD60x18 unlockTimeUD = ud(unlockTime);
        {
            UD60x18 tailFee = ud(tail.fee);
            UD60x18 treasuryCut = tailFee.mul(swap.TREASURY_CUT());
            UD60x18 reward = tailFee.sub(treasuryCut).sub(tailFee.mul(swap.MIN_LP_CUT())).mul(
                UNIT_60x18.sub(ud(tail.maturity - currentTime).div(unlockTimeUD))
            );
            assertEq(
                liabilitiesBefore + tailFee.sub(reward).sub(treasuryCut).unwrap(), swap.liabilities(), "liabilities after buyUnlock"
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
        UD60x18 headFee = ud(head.fee);
        uint256 expLiabilities =
            liabilitiesBefore + ud(head.fee).sub(headFee.mul(swap.TREASURY_CUT())).sub(headFee.mul(swap.RELAYER_CUT())).unwrap();
        assertEq(swap.liabilities(), expLiabilities, "liabilities after redeemUnlock");
        assertEq(swap.pendingRelayerRewards(address(this)), ud(head.fee).mul(swap.RELAYER_CUT()).unwrap(), "relayer rewards");
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
        swap.deposit(liquidity, 0);

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
}
