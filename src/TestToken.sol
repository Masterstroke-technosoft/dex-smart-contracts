// SPDX-License-Identifier: MIT

pragma solidity =0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract tMUSD is ERC20, ERC20Burnable, ERC20Pausable, Ownable2Step, ERC20Permit {

    address public blacklister;
    address public pendingBlacklister;
    mapping(address => bool) internal _blacklisted;
    mapping(address => bool) public isProtectedFromBlacklist;

    uint256 public mintCap;

    event Blacklisted(address indexed account);
    event UnBlacklisted(address indexed account);
    event BlacklisterChanged(address indexed newBlacklister);
    event BlacklisterTransferStarted(address indexed previousBlacklister, address indexed newBlacklister);
    event ProtectedAddressUpdated(address indexed account, bool isProtected);
    event MintCapUpdated(uint256 previousCap, uint256 newCap);

    error AccountBlacklisted(address account);
    error CallerNotBlacklister(address caller);
    error CallerNotPendingBlacklister(address caller);
    error AddressIsProtected(address account);
    error MintCapExceeded(uint256 requestedSupply, uint256 cap);
    error OwnershipRenunciationDisabled();

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
        ERC20Permit("tMUSD Coin")
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

    function renounceOwnership() public view override onlyOwner {
        revert OwnershipRenunciationDisabled();
    }

    function mint(address to, uint256 amount) public onlyOwner notBlacklisted(to) {
        require(to != address(0), "tMUSD: mint to zero address");
        if (mintCap != 0) {
            uint256 newSupply = totalSupply() + amount;
            if (newSupply > mintCap) revert MintCapExceeded(newSupply, mintCap);
        }
        _mint(to, amount);
    }

    function setMintCap(uint256 newCap) external onlyOwner {
        emit MintCapUpdated(mintCap, newCap);
        mintCap = newCap;
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

    function setProtectedAddress(address account, bool isProtected) external onlyOwner {
        isProtectedFromBlacklist[account] = isProtected;
        emit ProtectedAddressUpdated(account, isProtected);
    }

    function blacklist(address account) external onlyBlacklister {
        require(account != address(0), "tMUSD: zero address");
        if (isProtectedFromBlacklist[account]) revert AddressIsProtected(account);
        _blacklisted[account] = true;
        emit Blacklisted(account);
    }

    function unBlacklist(address account) external onlyBlacklister {
        require(_blacklisted[account], "tMUSD: account not blacklisted");
        _blacklisted[account] = false;
        emit UnBlacklisted(account);
    }

    function updateBlacklister(address newBlacklister) external onlyOwner {
        require(newBlacklister != address(0), "tMUSD: new blacklister is the zero address");
        pendingBlacklister = newBlacklister;
        emit BlacklisterTransferStarted(blacklister, newBlacklister);
    }

    function acceptBlacklister() external {
        if (msg.sender != pendingBlacklister) revert CallerNotPendingBlacklister(msg.sender);
        blacklister = pendingBlacklister;
        pendingBlacklister = address(0);
        emit BlacklisterChanged(blacklister);
    }

    function approve(address spender, uint256 value) public override returns (bool) {
        require(
            value == 0 || allowance(_msgSender(), spender) == 0,
            "tMUSD: reset allowance to zero first"
        );
        return super.approve(spender, value);
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(_msgSender(), spender, allowance(_msgSender(), spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        uint256 currentAllowance = allowance(_msgSender(), spender);
        require(currentAllowance >= subtractedValue, "tMUSD: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }
        return true;
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
    {
        if (value != 0) {
            _requireNotPaused();
            if (_blacklisted[owner]) revert AccountBlacklisted(owner);
            if (_blacklisted[spender]) revert AccountBlacklisted(spender);
        }
        super._approve(owner, spender, value, emitEvent);
    }

    function _spendAllowance(address owner, address spender, uint256 value)
        internal
        override
        notBlacklisted(spender)
    {
        super._spendAllowance(owner, spender, value);
    }
}
