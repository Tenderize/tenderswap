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

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Used for subgraph indexing and atomic deployments

contract SwapFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    event SwapDeployed(address underlying, address swap, address implementation);
    event SwapUpgraded(address underlying, address swap, address implementation);

    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    constructor() {
        _disableInitializers();
    }

    function deploy(ConstructorConfig memory cfg) external onlyOwner returns (address proxy, address implementation) {
        // Deploy the implementation
        implementation = address(new TenderSwap(cfg));
        // deploy the contract
        proxy = address(new ERC1967Proxy(implementation, abi.encodeWithSelector(TenderSwap.initialize.selector)));

        TenderSwap(proxy).transferOwnership(owner());

        emit SwapDeployed(address(cfg.UNDERLYING), proxy, implementation);
    }

    function upgrade(ConstructorConfig memory cfg, address swapProxy) external onlyOwner returns (address implementation) {
        if (TenderSwap(swapProxy).UNDERLYING() != cfg.UNDERLYING) {
            revert("SwapFactory: UNDERLYING_MISMATCH");
        }

        implementation = address(new TenderSwap(cfg));

        TenderSwap(swapProxy).upgradeTo(implementation);
    }

    ///@dev required by the OZ UUPS module
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner { }
}
