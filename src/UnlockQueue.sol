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

/**
 * @notice This file implements the necessary functionality for a double-ended queue or deque.
 * Elements can be popped from the front or back, but the deque can only be appended to.
 * It is used to store a list of unlocks for a given TenderSwap pool.
 */

pragma solidity >=0.8.19;

library UnlockQueue {
    error QueueEmpty();

    struct Item {
        uint256 id;
        uint128 amount;
        uint128 fee;
        uint256 maturity;
    }

    struct Node {
        Item data;
        uint256 next;
        uint256 prev;
    }

    struct Data {
        uint256 head; // oldest element
        uint256 tail; // newest element
        mapping(uint256 index => Node) nodes; // elements as a map
    }

    /**
     * @notice returns the oldest element in the queue
     */
    function head(UnlockQueue.Data storage q) internal view returns (Item memory) {
        return q.nodes[q.head].data;
    }

    /**
     * @notice returns the newest element in the queue
     */
    function tail(UnlockQueue.Data storage q) internal view returns (Item memory) {
        return q.nodes[q.tail].data;
    }

    /**
     * @notice Pop the oldest element from the queue
     * @param q The queue to pop from
     */
    function popFront(UnlockQueue.Data storage q) internal returns (Item memory unlock) {
        uint256 head = q.head;
        if (head == 0) revert QueueEmpty();

        unlock = q.nodes[head].data;

        uint256 next = q.nodes[head].next;
        if (next == 0) {
            q.head = 0;
            q.tail = 0;
        } else {
            q.head = next;
            q.nodes[next].prev = 0;
        }

        delete q.nodes[head];
    }

    /**
     * @notice Pop the newest element from the queue
     * @param q The queue to pop from
     */
    function popBack(UnlockQueue.Data storage q) internal returns (Item memory unlock) {
        uint256 tail = q.tail;
        if (tail == 0) revert QueueEmpty();

        unlock = q.nodes[tail].data;

        uint256 prev = q.nodes[tail].prev;
        if (prev == 0) {
            q.head = 0;
            q.tail = 0;
        } else {
            q.tail = prev;
            q.nodes[prev].next = 0;
        }

        delete q.nodes[tail];
    }

    /**
     * @notice Push a new element to the back of the queue
     * @param q The queue to push to
     * @param id The id of the unlock
     * @param unlock The unlock data to push
     */
    function push(UnlockQueue.Data storage q, uint256 id, Item memory unlock) internal {
        uint256 tail = q.tail;
        uint256 newTail = id;

        q.nodes[newTail].data = unlock;
        q.nodes[newTail].prev = tail;

        if (tail == 0) {
            q.head = newTail;
        } else {
            q.nodes[tail].next = newTail;
        }

        q.tail = newTail;
    }
}
