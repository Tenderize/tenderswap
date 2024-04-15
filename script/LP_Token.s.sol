// Matic Swap: 0x422BEF50e75098c3337790627689fF1aAA06C057
// Grt Swap: 0x7ee73bCa91f833C4E06BDC5F0e9f9aB7Ed9dB67d
// Lpt swap: 0x686962481543d543934903C3FE8bDe8c5dB9Bd97
import { Script, console2 } from "forge-std/Script.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { TenderSwap } from "@tenderize/swap/Swap.sol";

contract Add_Liquidity is Script {
    // Contracts are deployed deterministically.
    // e.g. `foo = new Foo{salt: salt}(constructorArgs)`
    // The presence of the salt argument tells forge to use https://github.com/Arachnid/deterministic-deployment-proxy
    bytes32 private constant salt = 0x0;

    // Start broadcasting with private key from `.env` file
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    address swap = 0x686962481543d543934903C3FE8bDe8c5dB9Bd97;

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        TenderSwap swap = TenderSwap(swap);
        address lpToken = address(swap.lpToken());
        console2.log("Lp Token :", lpToken);

        // ERC20(0x2eaC4210B90D13666f7E88635096BdC17C51FB70).approve(address(swap), 10 ether);

        // (uint256 out, uint256 fee) = swap.quote(0x2eaC4210B90D13666f7E88635096BdC17C51FB70, 10 ether);
        // console2.log("quote", out);
        // ERC20(0x2eaC4210B90D13666f7E88635096BdC17C51FB70).approve(address(swap), 10 ether);
        // // (out, fee) = swap.swap(0x2eaC4210B90D13666f7E88635096BdC17C51FB70, 10 ether, 0);
        // console2.log("out", out);
        // console2.log("fee", fee);

        // // Other Tenderizer: 0xD58Fed21106A046093086903909478AD96D310a8
        // (out, fee) = swap.quote(0xD58Fed21106A046093086903909478AD96D310a8, 10 ether);
        // console2.log("quote", out);

        vm.stopBroadcast();
    }
}
