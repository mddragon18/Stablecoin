// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import {Script} from "lib/forge-std/src/Script.sol";
import {DecentralisedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    DecentralisedStableCoin decentralisedStableCoin;
    DSCEngine dscEngine;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns(DecentralisedStableCoin,DSCEngine,HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed,address wbtcUsdPriceFeed,address weth,address wbtc,) = helperConfig.activeNetworkConfig();
        vm.startBroadcast();
        decentralisedStableCoin = new DecentralisedStableCoin();
        tokenAddresses = [weth,wbtc];
        priceFeedAddresses = [wethUsdPriceFeed,wbtcUsdPriceFeed];
        dscEngine = new DSCEngine(tokenAddresses,priceFeedAddresses,address(decentralisedStableCoin));
        decentralisedStableCoin.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        return (decentralisedStableCoin,dscEngine,helperConfig);
    }
}
