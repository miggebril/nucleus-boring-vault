// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Mock is ERC20 {
    uint256 public maxAmountAllowed = 100_000_000_000_000_000_000;

    constructor() ERC20("Mock XDAO", "MXDAO") { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 3;
    }
}
