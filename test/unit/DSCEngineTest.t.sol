// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import {Test,console} from "lib/forge-std/src/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralisedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";


contract DSCEngineTest is Test {
    error DSCEngine__MustBeMoreThanZero();
    DecentralisedStableCoin decentralisedStableCoin;
    DSCEngine dscEngine;
    DeployDSC deployDSC;
    HelperConfig helperConfig;

    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    
    uint256 public constant AMOUNT_COLLATERAL = 10;
    uint256 public constant STARTING_ERC20_BALANCE = 20;
    uint256 public constant COLLATERAL_DEPOSITED = 10;
    uint256 public constant COLLATERAL_REDEEMED = 1;
    uint256 public constant DSC_MINT = 100;
    uint256 public constant DSC_BURN = 5;
    uint256 public constant DSC_DEBT_TO_COVER = 1000;


    modifier depositCollateral() {
        vm.prank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL); 
        vm.prank(user);
        dscEngine.depositCollateral(weth, COLLATERAL_DEPOSITED);
        _;
    }

    function setUp() public {
        deployDSC = new DeployDSC();
        (decentralisedStableCoin,dscEngine,helperConfig) = deployDSC.run();
        (wethUsdPriceFeed,wbtcUsdPriceFeed,weth,wbtc,deployerKey) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(user2, STARTING_ERC20_BALANCE);
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUSDValue(weth, ethAmount);
        console.log(expectedUsd);
        console.log(actualUsd);
        assert(expectedUsd==actualUsd);
    }

    function testGetTokenValueFromUSD() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUSD(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }
    // depositCollateral
    function testRevertIfCollateralZero() public {
        vm.prank(user);
        ERC20Mock(weth).approve(address(dscEngine),AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
    }

    function testDepositCollateralForInvalidToken() public {
        ERC20Mock ranToken = new ERC20Mock();
        ERC20Mock(ranToken).mint(user, STARTING_ERC20_BALANCE);
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(ranToken),COLLATERAL_DEPOSITED);
    }

    function testDepositCollateralUpdatesBalance() public depositCollateral {
        (,uint256 collateralInUsd) = dscEngine.getAccountInformation(user);
        uint256 userCollateralBalance = dscEngine.getTokenAmountFromUSD(weth, collateralInUsd);
        assert(userCollateralBalance == COLLATERAL_DEPOSITED);
        assert(collateralInUsd==(COLLATERAL_DEPOSITED*2000));
    }

    function testMintDscRevertsIfAmountIsZero() public {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.mintDSC(0);
    }

    function testMintDscRevertsIfHealthFactorIsBroken() public {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorBroken.selector);
        dscEngine.mintDSC(DSC_MINT);
    }

    function testMintDscWorks() public depositCollateral {
        vm.prank(user);
        dscEngine.mintDSC(DSC_MINT);
        (uint256 dscMinted,) = dscEngine.getAccountInformation(user);
        assert(DSC_MINT==dscMinted);
        assert(DSC_MINT == decentralisedStableCoin.balanceOf(user));
    }

    function testDepositCollateralAndMintDSC() public  {
        vm.prank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL); 
        vm.prank(user);
        dscEngine.depositCollateralAndMintDSC(weth, COLLATERAL_DEPOSITED, DSC_MINT);

        (uint256 totalDsc , uint256 collateralInUsd) = dscEngine.getAccountInformation(user);
        uint256 tokenCollateral = dscEngine.getTokenAmountFromUSD(weth, collateralInUsd);
        assertEq(totalDsc,DSC_MINT);
        assertEq(tokenCollateral,COLLATERAL_DEPOSITED);
    }

    modifier DepositCollateralAndMintDsc() {
        vm.prank(user);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL); 
        vm.prank(user);
        dscEngine.depositCollateralAndMintDSC(weth, COLLATERAL_DEPOSITED, DSC_MINT);
        _;
    }

    // burnDsc 

    function testBurnDscRevertsIfZero() public {
        vm.prank(user);
        vm.expectRevert(DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.burnDSC(0);
    }

    function testBurnDscWorks() public DepositCollateralAndMintDsc {
        (uint256 dscBeforeBurn,) = dscEngine.getAccountInformation(user);
        vm.prank(user);
        decentralisedStableCoin.approve(address(dscEngine),DSC_BURN);
        vm.prank(user);
        dscEngine.burnDSC(DSC_BURN);
        (uint256 dscAfterBurn,) = dscEngine.getAccountInformation(user);
        assertEq(dscAfterBurn,dscBeforeBurn-DSC_BURN);
    }

    function testRedeemCollateral() public  DepositCollateralAndMintDsc {
        uint256 balanceOfUserBeforeRedeem = ERC20Mock(weth).balanceOf(user);
        vm.prank(user);
        dscEngine.redeemCollateral(weth, COLLATERAL_REDEEMED);
        uint256 balanceOfUserAfterRedeem = ERC20Mock(weth).balanceOf(user);
        assertEq(balanceOfUserAfterRedeem,balanceOfUserBeforeRedeem+COLLATERAL_REDEEMED);

    }

    function testRedeemCollateralForDsc() public DepositCollateralAndMintDsc {
        (uint256 dscBeforeBurn,) = dscEngine.getAccountInformation(user);
        uint256 balanceOfUserBeforeRedeem = ERC20Mock(weth).balanceOf(user);
        vm.prank(user);
        decentralisedStableCoin.approve(address(dscEngine),DSC_BURN);
        vm.prank(user);
        dscEngine.redeemCollateralForDSC(weth, COLLATERAL_REDEEMED, DSC_BURN);
        uint256 balanceOfUserAfterRedeem = ERC20Mock(weth).balanceOf(user);
        (uint256 dscAfterBurn,) = dscEngine.getAccountInformation(user);
        assertEq(balanceOfUserAfterRedeem,balanceOfUserBeforeRedeem+COLLATERAL_REDEEMED);
        assertEq(dscAfterBurn,dscBeforeBurn-DSC_BURN);
    }

    function testLiquidateRevertsIfHealthFactorIsFine() public DepositCollateralAndMintDsc() {
        vm.prank(user2);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsOk.selector);
        dscEngine.liquidate(weth, user, 10);
    }

    function testLiquidateRevertsIfDebtToCoverIsZero() public {
        vm.prank(user2);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.liquidate(weth, user, 0);
    }

    function testLiquidateWorks() public depositCollateral {

    // Setup: Break user's health factor
    vm.prank(user);
    dscEngine.mintDSC(10000); // Mint DSC
    console.log("User's health factor after minting:", dscEngine.getHealthFactor(user));

    // Setup liquidator (user2)
    vm.prank(user2);
    ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
    vm.prank(user2);
    dscEngine.depositCollateralAndMintDSC(weth, COLLATERAL_DEPOSITED, 5000);
    
    // Log initial states
    console.log("Initial user collateral value:", dscEngine.getAccountCollateralValue(user));
    console.log("Initial liquidator DSC balance:", decentralisedStableCoin.balanceOf(user2));

    // Break health factor
    MockV3Aggregator(wethUsdPriceFeed).updateAnswer(1500e8); // Significantly drop ETH price
    console.log("User's health factor after price drop:", dscEngine.getHealthFactor(user));

    // Prepare for liquidation
    vm.prank(user2);
    decentralisedStableCoin.approve(address(dscEngine), 5000);

    // Perform liquidation
    vm.prank(user2);
    dscEngine.liquidate(weth, user, 5000);

    // Assert liquidation worked
    uint256 userEndingCollateral = dscEngine.getAccountCollateralValue(user);
    uint256 liquidatorEndingDsc = decentralisedStableCoin.balanceOf(user2);
    
    console.log("Final user collateral value:", userEndingCollateral);
    console.log("Final liquidator DSC balance:", liquidatorEndingDsc);
    
    assert(userEndingCollateral < COLLATERAL_DEPOSITED * 2000); // Initial collateral value

    }

    // Invariant tests




}
