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

library WithdrawList {
    struct Request {
        uint256 withdrawable;
        uint256 available;
        address owner;
    }

    struct Node {
        Request request;
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
    function head(WithdrawList.Data storage q) internal view returns (Node memory) {
        return q.nodes[q._head];
    }

    /**
     * @notice Get the newest element in the queue
     * @param q The queue to query
     * @return The newest element in the queue
     */
    function tail(WithdrawList.Data storage q) internal view returns (Node memory) {
        return q.nodes[q._tail];
    }

    /**
     * @notice Get the element at a specific index in the queue
     * @param q The queue to query
     * @param id The index of the element to get
     * @return The element at the specified index
     */
    function itemAt(WithdrawList.Data storage q, uint256 id) internal view returns (Node memory) {
        return q.nodes[id];
    }

    /**
     * @notice Push a new element to the back of the queue
     * @param q The queue to push to
     * @param request The withdrawal request data to push
     */
    function push(WithdrawList.Data storage q, Request memory request) internal returns (uint256) {
        uint256 tail = q._tail;
        // This ensures when the queue is empty, the first element is at index 1
        // This distinguishes it from non-existing elements, which are at index 0
        uint256 newTail = tail + 1;

        q.nodes[newTail].request = request;
        q.nodes[newTail].prev = tail;

        if (tail == 0) {
            q._head = newTail;
        } else {
            q.nodes[tail].next = newTail;
        }

        q._tail = newTail;

        return newTail;
    }

    /**
     * @notice Update an element in the queue
     * @param q The queue to edit
     * @param id The index of the element to edit
     * @param request The new withdrawal request data
     */
    function update(WithdrawList.Data storage q, uint256 id, Request memory request) internal {
        q.nodes[id].request = request;
    }

    /**
     * @notice Remove an element from the queue
     * @param q The queue to remove from
     * @param id The index of the element to remove
     */
    function remove(WithdrawList.Data storage q, uint256 id) internal {
        uint256 next = q.nodes[id].next;
        uint256 prev = q.nodes[id].prev;

        if (next != 0) {
            q.nodes[next].prev = prev;
        } else {
            q._tail = prev;
        }

        if (prev != 0) {
            q.nodes[prev].next = next;
        } else {
            q._head = next;
        }

        delete q.nodes[id];
    }
}
