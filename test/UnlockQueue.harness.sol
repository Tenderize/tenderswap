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

import { UnlockQueue } from "@tenderize/swap/UnlockQueue.sol";

// solhint-disable func-name-mixedcase

contract UnlockQueueHarness {
    using UnlockQueue for UnlockQueue.Data;

    UnlockQueue.Data queue;

    function exposed_push(UnlockQueue.Item memory item) public {
        queue.push(item);
    }

    function exposed_popFront() public returns (UnlockQueue.Item memory item) {
        item = queue.popFront();
    }

    function exposed_popBack() public returns (UnlockQueue.Item memory item) {
        item = queue.popBack();
    }

    function exposed_head() public view returns (UnlockQueue.Item memory item) {
        item = queue.nodes[queue.head].data;
    }

    function exposed_tail() public view returns (UnlockQueue.Item memory item) {
        item = queue.nodes[queue.tail].data;
    }
}
