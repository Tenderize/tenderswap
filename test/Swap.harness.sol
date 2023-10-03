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

// solhint-disable func-name-mixedcase

contract SwapHarness is TenderSwap {
    constructor(Config memory config) TenderSwap(config) { }

    function exposed_setLiabilities(uint256 _liabilities) public {
        Data storage $ = _loadStorageSlot();
        $.liabilities = _liabilities;
    }
}
