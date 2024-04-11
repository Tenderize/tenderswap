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

pragma solidity ^0.8.20;

import { Owned } from "solmate/auth/Owned.sol";
import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TenderSwap, ConstructorConfig } from "@tenderize/swap/Swap.sol";

// Used for subgraph indexing and atomic deployments

contract SwapFactory is Owned {
    event SwapDeployed(address underlying, address swap, address implementation);
    event SwapUpgraded(address underlying, address swap, address implementation);

    constructor(address _owner) Owned(_owner) { }

    function deploy(ConstructorConfig memory cfg) external onlyOwner {
        // Deploy the implementation
        address implementation = address(new TenderSwap(cfg));
        // deploy the contract
        address instance = address(new ERC1967Proxy(implementation, ""));

        TenderSwap(instance).transferOwnership(owner);

        emit SwapDeployed(address(cfg.UNDERLYING), instance, implementation);
    }

    function upgrade(ConstructorConfig memory cfg, address swapProxy) external onlyOwner {
        if (TenderSwap(swapProxy).UNDERLYING() != cfg.UNDERLYING) {
            revert("SwapFactory: UNDERLYING_MISMATCH");
        }

        address implementation = address(new TenderSwap(cfg));

        TenderSwap(swapProxy).upgradeTo(implementation);
    }
}
