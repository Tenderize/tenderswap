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

import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TenderSwap, ConstructorConfig } from "@tenderize/swap/Swap.sol";

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Used for subgraph indexing and atomic deployments

contract SwapFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    error UNDERLYING_MISMATCH();

    event SwapDeployed(address underlying, address swap, address implementation);
    event SwapUpgraded(address underlying, address swap, address implementation, uint256 version);

    mapping(address pool => uint256 v) public version;

    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    constructor() {
        _disableInitializers();
    }

    function deploy(address implementation) external onlyOwner returns (address proxy) {
        uint256 v = 1;
        // deploy the contract
        proxy = address(new ERC1967Proxy{ salt: bytes32("tenderswap") }(implementation, ""));
        TenderSwap(proxy).initialize();
        TenderSwap(proxy).transferOwnership(owner());
        version[proxy] = v;
        emit SwapDeployed(address(TenderSwap(proxy).UNDERLYING()), proxy, implementation);
    }

    function upgrade(address newImplementation, address swapProxy) external onlyOwner returns (address implementation) {
        address underlying = address(TenderSwap(swapProxy).UNDERLYING());
        if (underlying != address(TenderSwap(newImplementation).UNDERLYING())) {
            revert UNDERLYING_MISMATCH();
        }

        uint256 v = ++version[swapProxy];

        TenderSwap(swapProxy).upgradeTo(implementation);

        emit SwapUpgraded(underlying, swapProxy, implementation, v);
    }

    ///@dev required by the OZ UUPS module
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner { }
}
