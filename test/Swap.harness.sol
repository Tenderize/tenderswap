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

import { TenderSwap, Config } from "@tenderize/swap/Swap.sol";
import { UnlockQueue } from "@tenderize/swap/UnlockQueue.sol";

// solhint-disable func-name-mixedcase

contract SwapHarness is TenderSwap {
    constructor(Config memory config) TenderSwap(config) { }

    function exposed_setLiabilities(uint256 _liabilities) public {
        Data storage $ = _loadStorageSlot();
        $.liabilities = _liabilities;
    }

    function exposed_queueQuery(uint256 index) public view returns (UnlockQueue.Node memory) {
        Data storage $ = _loadStorageSlot();
        return $.unlockQ.nodes[index];
    }

    function exposed_unlocking() public view returns (uint256) {
        Data storage $ = _loadStorageSlot();
        return $.unlocking;
    }

    function exposed_unlockingForAsset(address asset) public view returns (uint256) {
        Data storage $ = _loadStorageSlot();
        return $.unlockingForAsset[asset];
    }
}
