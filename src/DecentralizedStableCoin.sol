// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title   Decentralised Stable Coin
 * @author  mddragon18
 * @dev
 * @notice  .
 * collateral : Exo (wETH, wBTC)
 * Minting : Algorithmic
 * Relative stability: pegged to USD
 *
 * This contract is meant to governed by a DSCEngine. This is just a ERC20 implementation.
 */
contract DecentralisedStableCoin is ERC20Burnable, Ownable {
    error DecentralisedStableCoin__MustBeMoreThanZero();
    error DecentralisedStableCoin__BurnAmountExceedsBalance(uint256 balance, uint256 amount);
    error DecentralisedStableCoin__CannotMintToZeroAddress();

    constructor() ERC20("Decentralised Stable Coin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) revert DecentralisedStableCoin__MustBeMoreThanZero();
        if (balance < _amount) revert DecentralisedStableCoin__BurnAmountExceedsBalance(balance, _amount);
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) revert DecentralisedStableCoin__CannotMintToZeroAddress();
        if (_amount <= 0) revert DecentralisedStableCoin__MustBeMoreThanZero();
        _mint(_to, _amount);
        return true;
    }
}
