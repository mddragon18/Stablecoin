// Invariants:
// 1. The total supply of dsc should be less than the total collateral value.
// 2. Getter view functions should never revert.

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
 
import {Test,console} from "lib/forge-std/src/Test.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {InvariantHandler} from "test/fuzz/InvariantHandler.t.sol";

contract InvariantTests is StdInvariant,Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralisedStableCoin dsc;
    HelperConfig helperConfig;
    InvariantHandler handler;

    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    address user = makeAddr("user");
    uint256 public constant STARTING_ERC20_BALANCE = 20;



    function setUp() external {
        deployer = new DeployDSC();
        console.log("DeployDSC success");
        (dsc,dscEngine,helperConfig) = deployer.run();
        console.log("DeployDSC run success");
        handler = new InvariantHandler(dscEngine,dsc);
        console.log("Handler deploy success");
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,deployerKey) = helperConfig.activeNetworkConfig();
        console.log("weth:",weth);
        console.log("wbtc:",wbtc);
        targetContract(address(handler));
        console.log("targetContract success");
    }

    function invariant_totalSupplyLessThanCollateralValue() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWeth = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtc = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 totalCollateralValue = dscEngine.getUSDValue(weth, totalWeth) + dscEngine.getUSDValue(wbtc, totalWbtc) ;
        console.log(handler.count());
        assert(totalSupply <= totalCollateralValue);
    }

}
