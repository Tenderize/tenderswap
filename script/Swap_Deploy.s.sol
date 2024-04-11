// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Script, console2 } from "forge-std/Script.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { TenderSwap, ConstructorConfig } from "@tenderize/swap/Swap.sol";
import { SwapFactory } from "@tenderize/swap/Factory.sol";
import { SD59x18 } from "@prb/math/SD59x18.sol";

address constant FACTORY = address(0);

contract Swap_Deploy is Script {
    // Contracts are deployed deterministically.
    // e.g. `foo = new Foo{salt: salt}(constructorArgs)`
    // The presence of the salt argument tells forge to use https://github.com/Arachnid/deterministic-deployment-proxy
    bytes32 private constant salt = 0x0;

    // Start broadcasting with private key from `.env` file
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address underlying = vm.envAddress("UNDERLYING");
    address registry = vm.envAddress("REGISTRY");
    address unlocks = vm.envAddress("UNLOCKS");
    ConstructorConfig cfg =
        ConstructorConfig({ UNDERLYING: ERC20(underlying), BASE_FEE: SD59x18.wrap(0.0005e18), K: SD59x18.wrap(3e18) });

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        TenderSwap swap = new TenderSwap{ salt: salt }(cfg);
        console2.log("TenderSwap deployed at: ", address(swap));
        vm.stopBroadcast();
    }
}
