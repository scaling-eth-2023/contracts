// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ProtocolA is ERC20 {
    IERC20 tokenA;

    constructor(address tokenAAddress) ERC20("TOKENB", "TKB") {
        tokenA = IERC20(tokenAAddress);
    }

    // User swaps their token A with the exact same amount of token B.
    function swapExactTokenAWithTokenB(uint256 _amount) external {
        uint256 userTokenABalance = tokenA.balanceOf(msg.sender);
        require(
            userTokenABalance >= _amount,
            "USER DOESN'T HAVE ENOUGH TOKEN A BALANCE"
        );

        uint256 allowance = tokenA.allowance(msg.sender, address(this));
        require(allowance >= _amount, "NOT ENOUGH ALLOWANCE");

        tokenA.transferFrom(msg.sender, address(this), _amount);
        _mint(msg.sender, _amount);
    }

    function swapExactTokenBWithTokenA(uint256 _amount) external {
        uint256 userTokenBBalance = balanceOf(msg.sender);
        require(
            userTokenBBalance >= _amount,
            "USER DOESN'T HAVE ENOUGH TOKEN B BALANCE"
        );

        uint256 allowance = allowance(msg.sender, address(this));
        require(allowance >= _amount, "NOT ENOUGH ALLOWANCE");

        tokenA.transfer(msg.sender, _amount);
        _burn(msg.sender, _amount);
    }
}
