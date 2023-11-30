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
import { UnlockQueue } from "@tenderize/swap/UnlockQueue.sol";
import { UnlockQueueHarness } from "./UnlockQueue.harness.sol";

contract UnlockQueueTest is Test {
    UnlockQueueHarness queue;

    function setUp() public {
        queue = new UnlockQueueHarness();
    }

    function test_queue() public {
        UnlockQueue.Item memory item1 = UnlockQueue.Item({ id: 1, amount: 2, fee: 3, maturity: 4 });
        UnlockQueue.Item memory item2 = UnlockQueue.Item({ id: 2, amount: 5, fee: 9, maturity: 20 });
        UnlockQueue.Item memory item3 = UnlockQueue.Item({ id: 3, amount: 9, fee: 12, maturity: 31 });

        queue.exposed_push(item1);

        // assert
        assertEq(queue.exposed_head().data.id, 1);
        assertEq(queue.exposed_tail().data.id, 1);

        queue.exposed_push(item2);
        // assert
        assertEq(queue.exposed_head().data.id, 1);
        assertEq(queue.exposed_head().prev, 0);
        assertEq(queue.exposed_head().next, 2);
        assertEq(queue.exposed_tail().data.id, 2);

        queue.exposed_push(item3);
        // assert
        assertEq(queue.exposed_head().data.id, 1);
        assertEq(queue.exposed_head().prev, 0);
        assertEq(queue.exposed_head().next, 2);
        assertEq(queue.exposed_tail().data.id, 3);
        assertEq(queue.exposed_tail().prev, 2);
        assertEq(queue.exposed_tail().next, 0);

        // pop front
        UnlockQueue.Node memory popped = queue.exposed_popHead();
        assertEq(popped.data.id, 1);
        assertEq(queue.exposed_head().data.id, 2);

        // pop back
        popped = queue.exposed_popTail();
        assertEq(popped.data.id, 3);
        assertEq(queue.exposed_head().data.id, 2);
        assertEq(queue.exposed_tail().data.id, 2);
    }
}
