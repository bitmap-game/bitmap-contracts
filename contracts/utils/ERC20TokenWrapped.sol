// SPDX-License-Identifier: GPL-3.0
// Implementation of permit based on https://github.com/WETH10/WETH10/blob/main/contracts/WETH10.sol
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";

contract ERC20TokenWrapped is ERC20Permit, ERC20Capped {
    // Decimals
    uint8 private immutable _decimals;

    string public constant version = "1.2.0";

    constructor(
        string memory name,
        string memory symbol,
        uint8 __decimals,
        uint256 __cap
    ) ERC20(name, symbol) ERC20Permit(name) ERC20Capped(__cap){
        _decimals = __decimals;
    }

    function mint(address to, uint256 value) external {
        _mint(to, value);
    }

    // Notice that is not require to approve wrapped tokens to use the bridge
    function burn(address account, uint256 value) external {
        _burn(account, value);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    // Blacklist restrict from-address, contains(burn's from-address)
    function _update(address from, address to, uint256 value) override(ERC20, ERC20Capped) internal virtual {
        ERC20Capped._update(from, to, value);
    }
}
