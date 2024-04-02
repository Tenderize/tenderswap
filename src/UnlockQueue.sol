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
    error IdExists();

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
        uint256 _head; // oldest element
        uint256 _tail; // newest element
        mapping(uint256 index => Node) nodes; // elements as a map
    }

    /**
     * @notice Get the oldest element in the queue
     * @param q The queue to query
     * @return The oldest element in the queue
     */
    function head(UnlockQueue.Data storage q) internal view returns (Node memory) {
        return q.nodes[q._head];
    }

    /**
     * @notice Get the newest element in the queue
     * @param q The queue to query
     * @return The newest element in the queue
     */
    function tail(UnlockQueue.Data storage q) internal view returns (Node memory) {
        return q.nodes[q._tail];
    }

    /**
     * @notice Pop the oldest element from the queue
     * @param q The queue to pop from
     */
    function popHead(UnlockQueue.Data storage q) internal returns (Node memory node) {
        uint256 head = q._head;
        if (head == 0) revert QueueEmpty();

        node = q.nodes[head];

        uint256 next = q.nodes[head].next;
        if (next == 0) {
            q._head = 0;
            q._tail = 0;
        } else {
            q._head = next;
            q.nodes[next].prev = 0;
        }

        delete q.nodes[head];
    }

    /**
     * @notice Pop the newest element from the queue
     * @param q The queue to pop from
     */
    function popTail(UnlockQueue.Data storage q) internal returns (Node memory node) {
        uint256 tail = q._tail;
        if (tail == 0) revert QueueEmpty();

        node = q.nodes[tail];

        uint256 prev = q.nodes[tail].prev;
        if (prev == 0) {
            q._head = 0;
            q._tail = 0;
        } else {
            q._tail = prev;
            q.nodes[prev].next = 0;
        }

        delete q.nodes[tail];
    }

    /**
     * @notice Push a new element to the back of the queue
     * @param q The queue to push to
     * @param unlock The unlock data to push
     */
    function push(UnlockQueue.Data storage q, Item memory unlock) internal {
        uint256 tail = q._tail;
        uint256 newTail = unlock.id;

        if (tail != 0) {
            if (q.nodes[newTail].data.id != 0) revert IdExists();
        }

        q.nodes[newTail].data = unlock;
        q.nodes[newTail].prev = tail;

        if (tail == 0) {
            q._head = newTail;
        } else {
            q.nodes[tail].next = newTail;
        }

        q._tail = newTail;
    }
}
