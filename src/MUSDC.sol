// SPDX-License-Identifier: MIT

pragma solidity =0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MUSDC is ERC20, ERC20Burnable, ERC20Pausable, Ownable2Step, ERC20Permit {
    uint256 public immutable maxSupply;

    address public blacklister;
    address public pendingBlacklister;

    mapping(address => bool) internal _blacklisted;

    mapping(address => bool) public protectedFromBlacklist;

    event Blacklisted(address indexed account);
    event UnBlacklisted(address indexed account);
    event BlacklisterTransferStarted(address indexed previousBlacklister, address indexed newBlacklister);
    event BlacklisterChanged(address indexed newBlacklister);
    event BlacklistProtectionSet(address indexed account, bool protectedStatus);

    error AccountBlacklisted(address account);
    error CallerNotBlacklister(address caller);
    error AccountProtected(address account);
    error AccountNotBlacklisted(address account);
    error MaxSupplyExceeded(uint256 attempted, uint256 cap);
    error RenounceDisabled();

    modifier onlyBlacklister() {
        if (msg.sender != blacklister) revert CallerNotBlacklister(msg.sender);
        _;
    }

    modifier notBlacklisted(address account) {
        if (_blacklisted[account]) revert AccountBlacklisted(account);
        _;
    }

    constructor(address initialOwner, uint256 maxSupply_)
        ERC20("MUSD Coin", "MUSDC")
        Ownable(initialOwner)
        ERC20Permit("MUSD Coin")
    {
        require(maxSupply_ > 0, "MUSDC: zero max supply");
        maxSupply = maxSupply_;
        blacklister = initialOwner;
        emit BlacklisterChanged(initialOwner);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    
    function mint(address to, uint256 amount) public onlyOwner notBlacklisted(to) {
        require(to != address(0), "MUSDC: mint to zero address");
        uint256 currentSupply = totalSupply();
        uint256 remaining = maxSupply - currentSupply;
        if (amount > remaining) revert MaxSupplyExceeded(amount, remaining);
        _mint(to, amount);
    }

    function burn(uint256 value) public override notBlacklisted(msg.sender) {
        super.burn(value);
    }

    function burnFrom(address account, uint256 value)
        public
        override
        notBlacklisted(msg.sender)
        notBlacklisted(account)
    {
        super.burnFrom(account, value);
    }

    function transferFrom(address from, address to, uint256 value)
        public
        override
        notBlacklisted(msg.sender)
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function renounceOwnership() public view override onlyOwner {
        revert RenounceDisabled();
    }

    function transferBlacklister(address newBlacklister) external onlyOwner {
        require(newBlacklister != address(0), "MUSDC: zero blacklister");
        pendingBlacklister = newBlacklister;
        emit BlacklisterTransferStarted(blacklister, newBlacklister);
    }

    function acceptBlacklister() external {
        require(msg.sender == pendingBlacklister, "MUSDC: caller is not pending blacklister");
        blacklister = pendingBlacklister;
        pendingBlacklister = address(0);
        emit BlacklisterChanged(blacklister);
    }

    function setBlacklistProtection(address account, bool isProtected) external onlyOwner {
        require(account != address(0), "MUSDC: zero address");
        protectedFromBlacklist[account] = isProtected;
        emit BlacklistProtectionSet(account, isProtected);
    }

    function blacklist(address account) external onlyBlacklister {
        require(account != address(0), "MUSDC: zero address");
        if (protectedFromBlacklist[account]) revert AccountProtected(account);
        _blacklisted[account] = true;
        emit Blacklisted(account);
    }

    function unBlacklist(address account) external onlyBlacklister {
        if (!_blacklisted[account]) revert AccountNotBlacklisted(account);
        _blacklisted[account] = false;
        emit UnBlacklisted(account);
    }

    function isBlacklisted(address account) external view returns (bool) {
        return _blacklisted[account];
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
        notBlacklisted(from)
        notBlacklisted(to)
    {
        super._update(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal override {
        if (value != 0) {
            _requireNotPaused();
            if (_blacklisted[owner]) revert AccountBlacklisted(owner);
            if (_blacklisted[spender]) revert AccountBlacklisted(spender);
        }
        super._approve(owner, spender, value, emitEvent);
    }
}
