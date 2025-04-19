// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DecentralisedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @author  mddragon18
 * @title   DSCEngine
 * @dev     .
 * @notice  This is the core of the stablecoin system. It is responsible for minting and burning the stablecoin, as well as managing the collateral.
 * The system is designed to be as minimal as possible, and have tokens maintain a 1 token = 1 USD peg.
 * Our system must always be overcollateralized. This means that the value of the collateral must always be greater than the value of the stablecoin.
 * --Exogenous Collateral
 * --Algorithmic Minting
 * --Pegged
 * If the borrower has less collateral than a threshold of 200% , then his position will be liquidate and the collateral will be sold to buying customers at * a discount.
 */
contract DSCEngine is ReentrancyGuard {
    // ERRORS
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeEqual();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBroken();
    error DSCEngine__HealthFactorIsOk();
    error DSCEngine__HealthFactorNotImproved();

    // state variables
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address pricefeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountMinted) private s_dscMinted;
    address[] private s_collateralTokens;
    DecentralisedStableCoin private immutable i_dsc;

    // EVENTS
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    // MODIFIERS
    modifier moreThanZero(uint256 value) {
        if (value <= 0) revert DSCEngine__MustBeMoreThanZero();
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) revert DSCEngine__TokenNotAllowed();
        _;
    }

    /// @notice Constructor initialises the tokens which are to used as collaterals and their respective price feeds.
    /// @param tokenAddresses an array of addresses of the tokens which are to be used as collaterals.
    /// @param priceFeedAddresses an array of addresses of the price feeds of the tokens which are to be used as collaterals.
    /// @param dscAddress the address of the DSC contract.
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeEqual();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralisedStableCoin(dscAddress);
    }

    // External Functions

    /**
     * @notice  This is the function that will be called when the user wants to deposit collateral and mint DSC.
     * @dev     .
     * @param   _tokenCollateralAddress  The address of the collateral token
     * @param   amountCollateral  Amount of the collateral token to be deposited
     * @param   amountDSCToMint  Amount of the DSC to be minted
     */
    function depositCollateralAndMintDSC(
        address _tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(_tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /**
     * @notice  This is the function that will be called when the user wants to deposit collateral.
     * @dev     Using the IERC20 interface to interact with the collateral token's contract.
     * @param   _tokenCollateralAddress  The address of the token to be deposited as collateral.
     * @param   amount  The amount of collateral to be deposited.
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 amount)
        public
        moreThanZero(amount)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += amount;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, amount);
        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), amount);
        if (!success) revert DSCEngine__TransferFailed();
    }

    /**
     * @notice Redeems collateral for Decentralized Stablecoin (DSC).
     * @dev This function allows a user to redeem a specified amount of collateral
     *      in exchange for a specified amount of DSC. The caller must ensure they
     *      have sufficient collateral and DSC balance to perform the redemption.
     * @param tokenCollateralAddress The address of the collateral token to be redeemed.
     * @param amountCollateral The amount of collateral to redeem.
     * @param amountDsc The amount of DSC to exchange for the collateral.
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDsc)
        external
    {
        burnDSC(amountDsc);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    // to redeem collateral , healthFactor > 1 after redeem.
    function redeemCollateral(address tokenCollateralAddress, uint256 amount)
        public
        moreThanZero(amount)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amount);
        _revertIfHealthFactorIsBroken();
    }

    /**
     * @notice  Mint DSC if the user has enough collateral.
     * @dev The user must have 200% over collateralization to mint DSC.We will use the health factor to check this
     * @dev     The function will revert if the user does not have enough collateral.
     * @param   amountDSCToMint  The amount of DSC to be minted.
     */
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) {
        s_dscMinted[msg.sender] += amountDSCToMint;
        _revertIfHealthFactorIsBroken();
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) revert DSCEngine__TransferFailed();
    }

    function burnDSC(uint256 amountToBurn) public moreThanZero(amountToBurn) {
        _burnDsc(amountToBurn, msg.sender, msg.sender);
    }

    /**
     * @notice  You can partially liquidate a user.
     * @dev     .
     * @param   collateral  The address of the erc20 collateral.
     * @param   user  The user's address whose healthFactor is broken
     * @param   debtToCover  The amount to DSC to burn to liquidate.
     * To liquidate a user , his health factor must be less than the MINIMUM_HEALTH_FACTOR(1e18).
     * To liquidate positions , a 10% liquidation bonus is given to the liquidator.
     * The liquidator will get the collateral at a 10% discount.
     * if $100 ETH / $50 DSC , then the liquidator will get $55 worth of ETH.
     * Since we can't deal in dollars we will convert the amount of usd to the native token of the collateral
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startUserHealthFactor = _healthFactor(user);
        if (startUserHealthFactor >= 1e18) {
            revert DSCEngine__HealthFactorIsOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered) * LIQUIDATION_BONUS / 100;
        uint256 totalCollateral = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(user, msg.sender, collateral, totalCollateral);
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endUserHealthFactor = _healthFactor(user);
        if (endUserHealthFactor <= startUserHealthFactor) revert DSCEngine__HealthFactorNotImproved();
        _revertIfHealthFactorIsBroken();
    }

    function getTokenAmountFromUSD(address collateral, uint256 amountInUsd)
        public
        view
        moreThanZero(amountInUsd)
        returns (uint256 amountOfToken)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateral]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        amountOfToken = (amountInUsd * 1e18) / (uint256(price) * 1e10);
    }

    /**
     * @notice  Burn the specified amount of DSC from a user.
     * @dev     Function can only be called by trusted functions which perform security checks before this.
     * @param   amountToBurn  The DSC amount to be burnt.
     * @param   onBehalfOf  The user whose debt is being paid.
     * @param   dscFrom  The user who is paying off the debt.
     * First we perform internal accounting and transfer the tokens to DSCEngine contract and remove them from supply by using the burn function from i_dsc.
     */
    function _burnDsc(uint256 amountToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountToBurn);
        if (!success) revert DSCEngine__TransferFailed();
        i_dsc.burn(amountToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amount) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amount;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amount);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amount);
        if (!success) revert DSCEngine__TransferFailed();
    }

    // VIEW and PURE functions

    // internal view and pure

    /**
     * @notice  Obtain the health factor of the user.
     * @dev     LIQUIDATION_THRESHOLD is set to 50 , so that we have an overcollateralization of 200% to mint DSC.
     * @param   user  Address of the user whose health factor is to be calculated.
     * @return  uint256  The value of health factor.
     */
    function _healthFactor(address user) internal view returns (uint256) {
        //total dsc minted and total value of collateral is needed
        (uint256 totalDscMinted, uint256 totalCollateralValue) = _getAccountInformation(user);
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralValueAdjustedToThreshold = (totalCollateralValue * LIQUIDATION_THRESHOLD) / 100;
        return (collateralValueAdjustedToThreshold * 1e18 / totalDscMinted);
    }

    /**
     * @notice  Controls the execution of mintDSC function,
     */
    function _revertIfHealthFactorIsBroken() internal view {
        uint256 healthFactor = _healthFactor(msg.sender);
        if (healthFactor < 1e18) {
            revert DSCEngine__HealthFactorBroken();
        }
    }

    function _getAccountInformation(address user)
        internal
        view
        returns (uint256 _totalDscMinted, uint256 _totalCollateralValue)
    {
        uint256 totalDscMinted = s_dscMinted[user];
        uint256 totalCollateralValue = getAccountCollateralValue(user);
        return (totalDscMinted, totalCollateralValue);
    }

    // PUBLIC VIEW & PURE

    function getHealthFactor(address user) public view returns (uint256) {
        return _healthFactor(user);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
    }

    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralInUsd)
    {
        (totalDscMinted, totalCollateralInUsd) = _getAccountInformation(user);
    }

    /**
     * @notice  Convert the amount of token to its USD value.
     * @dev     We are using AggregatorV3Interface and using the pricefeeds we stored in s_priceFeeds mapping.
     * @param   token  Address of the token whose value is to be calculated.
     * @param   amount  Amount of the above token.
     * @return  uint256  The value of the token in USD.
     */
    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((amount * uint256(price) * 1e10) / 1e18);
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) public view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
}
