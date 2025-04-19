//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralisedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract InvariantHandler is Test {
    DSCEngine dscEngine;
    DecentralisedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 public count = 0;
    address[] public s_depositedCollateral;

    constructor(DSCEngine _dscEngine, DecentralisedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, type(uint96).max);

        vm.prank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        vm.prank(msg.sender);
        collateral.approve(address(dscEngine), amountCollateral);
        vm.prank(msg.sender);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        s_depositedCollateral.push(msg.sender);
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (s_depositedCollateral.length == 0) return;
        address sender = s_depositedCollateral[addressSeed % s_depositedCollateral.length];
        (uint256 totalDscMinted, uint256 collateral) = dscEngine.getAccountInformation(sender);

        int256 maxDscToMint = int256((collateral / 2)) - int256(totalDscMinted);
        if (maxDscToMint < 0) return;

        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) return;

        vm.prank(sender);
        dscEngine.mintDSC(amount);
        count++;
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) return;
        vm.prank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }

    // Helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) return weth;
        return wbtc;
    }
}
