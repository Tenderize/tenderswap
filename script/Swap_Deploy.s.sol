// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Script, console2 } from "forge-std/Script.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { TenderSwap, ConstructorConfig } from "@tenderize/swap/Swap.sol";
import { SwapFactory } from "@tenderize/swap/Factory.sol";
import { UD60x18 } from "@prb/math/UD60x18.sol";
import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

// TENDERIZE POOLS BASE FEE = 0.025% with K=4
// EXOTIC POOLS BASE FEE = 0.1% with K=4

address constant FACTORY = address(0);

contract Swap_Deploy is Script {
    // Contracts are deployed deterministically.
    // e.g. `foo = new Foo{salt: salt}(constructorArgs)`
    // The presence of the salt argument tells forge to use https://github.com/Arachnid/deterministic-deployment-proxy
    bytes32 private constant salt = 0x0;

    // Start broadcasting with private key from `.env` file
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address underlying = vm.envAddress("UNDERLYING");

    // TENDERIZE POOLS
    UD60x18 BASE_FEE = UD60x18.wrap(0.0005e18); // 0.05%
    UD60x18 K = UD60x18.wrap(5e18);

    // EXOTIC POOLS
    // UD60x18 BASE_FEE = UD60x18.wrap(0.001e18); // 0.1%
    // UD60x18 K = UD60x18.wrap(4e18);
    ConstructorConfig cfg = ConstructorConfig({ UNDERLYING: ERC20(underlying), BASE_FEE: BASE_FEE, K: K });

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        address implementation = address(new TenderSwap{ salt: bytes32(uint256(1)) }(cfg));
        (address proxy) = SwapFactory(FACTORY).deploy(implementation);
        console2.log("Deployment for ", underlying);
        console2.log("TenderSwap deployed at: ", proxy);
        console2.log("Implementation deployed at: ", implementation);
        vm.stopBroadcast();
    }
}
