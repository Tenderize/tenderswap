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

import { ERC20 } from "solmate/tokens/ERC20.sol";

contract LPToken is ERC20 {
    uint8 private constant DECIMALS = 18;
    address private immutable owner;

    error Unauthorized();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(string memory _name, string memory _symbol) ERC20(_encodeName(_name), _encodeSymbol(_symbol), DECIMALS) {
        owner = msg.sender;
    }

    function mint(address to, uint256 value) public onlyOwner {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public onlyOwner {
        _burn(from, value);
    }

    function _encodeName(string memory _name) internal pure returns (string memory) {
        return string(abi.encodePacked("TenderSwap", " ", _name));
    }

    function _encodeSymbol(string memory _symbol) internal pure returns (string memory) {
        return string(abi.encodePacked("tSWAP", " ", _symbol));
    }
}
