// SPDX-License-Identifier: MIT

pragma solidity =0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract tMUSD is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ERC20Permit {

    address public blacklister;
    mapping(address => bool) internal _blacklisted;

    event Blacklisted(address indexed account);
    event UnBlacklisted(address indexed account);
    event BlacklisterChanged(address indexed newBlacklister);

    error AccountBlacklisted(address account);
    error CallerNotBlacklister(address caller);

    modifier onlyBlacklister() {
        if (msg.sender != blacklister) revert CallerNotBlacklister(msg.sender);
        _;
    }

    modifier notBlacklisted(address account) {
        if (_blacklisted[account]) revert AccountBlacklisted(account);
        _;
    }

    constructor(address initialOwner)
        ERC20("tMUSD Coin", "tMUSDC")
        Ownable(initialOwner)
        ERC20Permit("tMUSDC")
    {
        blacklister = initialOwner;
        emit BlacklisterChanged(initialOwner);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyOwner notBlacklisted(to) {
        require(to != address(0), "tMUSD: mint to zero address");
        _mint(to, amount);
    }

    function burn(uint256 value) public override notBlacklisted(msg.sender) {
        super.burn(value);
    }

    function burnFrom(address account, uint256 value) public override notBlacklisted(msg.sender) notBlacklisted(account) {
        super.burnFrom(account, value);
    }

    function isBlacklisted(address account) external view returns (bool) {
        return _blacklisted[account];
    }

    function blacklist(address account) external onlyBlacklister {
        require(account != address(0), "tMUSD: zero address");
        _blacklisted[account] = true;
        emit Blacklisted(account);
    }

    function unBlacklist(address account) external onlyBlacklister {
        _blacklisted[account] = false;
        emit UnBlacklisted(account);
    }

    function updateBlacklister(address newBlacklister) external onlyOwner {
        require(newBlacklister != address(0), "new blacklister is the zero address");
        blacklister = newBlacklister;
        emit BlacklisterChanged(newBlacklister);
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
        notBlacklisted(from)
        notBlacklisted(to)
    {
        super._update(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value, bool emitEvent)
        internal
        override
        notBlacklisted(owner)
        notBlacklisted(spender)
    {
        super._approve(owner, spender, value, emitEvent);
    }
}
