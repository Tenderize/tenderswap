// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Script, console2 } from "forge-std/Script.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { TenderSwap, Config } from "@tenderize/swap/Swap.sol";

contract Swap_Deploy is Script {
    // Contracts are deployed deterministically.
    // e.g. `foo = new Foo{salt: salt}(constructorArgs)`
    // The presence of the salt argument tells forge to use https://github.com/Arachnid/deterministic-deployment-proxy
    bytes32 private constant salt = bytes32(uint256(1));

    // Start broadcasting with private key from `.env` file
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address underlying = vm.envAddress("UNDERLYING");
    address registry = vm.envAddress("REGISTRY");
    address unlocks = vm.envAddress("UNLOCKS");
    Config cfg = Config({ underlying: ERC20(underlying), registry: registry, unlocks: unlocks });

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        TenderSwap swap = new TenderSwap{salt: salt}(cfg);
        console2.log("TenderSwap deployed at: ", address(swap));
        vm.stopBroadcast();
    }
}
