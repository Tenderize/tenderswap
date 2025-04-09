pragma solidity 0.8.20;

import { Script, console2 } from "forge-std/Script.sol";
import { TenderSwap, ConstructorConfig } from "@tenderize/swap/Swap.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { UD60x18 } from "@prb/math/UD60x18.sol";

address constant LPT = 0x289ba1701C2F088cf0faf8B3705246331cB8A839;
address constant GRT = 0x9623063377AD1B27544C965cCd7342f7EA7e88C7;

contract SwapUpgrade is Script {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    bytes32 private constant salt = bytes32(uint256(1));

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        UD60x18 BASE_FEE = UD60x18.wrap(0.0005e18); // 0.05%
        UD60x18 K = UD60x18.wrap(5e18);

        ConstructorConfig memory cfg = ConstructorConfig({ UNDERLYING: ERC20(LPT), BASE_FEE: BASE_FEE, K: K });
        address lpt_swap = address(new TenderSwap{ salt: salt }(cfg));
        cfg.UNDERLYING = ERC20(GRT);
        address grt_swap = address(new TenderSwap{ salt: salt }(cfg));

        console2.log("LPT Swap deployed at: ", lpt_swap);
        console2.log("GRT Swap deployed at: ", grt_swap);
        vm.stopBroadcast();
    }
}
