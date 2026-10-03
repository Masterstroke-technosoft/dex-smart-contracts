// SPDX-License-Identifier: MIT

pragma solidity =0.8.27;

contract WMSTC {
    string public constant name = "Wrapped MSTC";
    string public constant symbol = "WMSTC";
    uint8 public constant decimals = 18;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bool private _locked;

    modifier nonReentrant() {
        require(!_locked, "WMSTC: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        require(msg.value > 0, "WMSTC: zero deposit");
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public nonReentrant {
        require(balanceOf[msg.sender] >= wad, "WMSTC: insufficient balance");
        balanceOf[msg.sender] -= wad;
        emit Withdrawal(msg.sender, wad);
        (bool ok, ) = msg.sender.call{value: wad}("");
        require(ok, "WMSTC: native transfer failed");
    }

    function totalSupply() public view returns (uint256) {
        return address(this).balance;
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function increaseAllowance(address guy, uint256 addedValue) external returns (bool) {
        uint256 updated = allowance[msg.sender][guy] + addedValue;
        allowance[msg.sender][guy] = updated;
        emit Approval(msg.sender, guy, updated);
        return true;
    }

    function decreaseAllowance(address guy, uint256 subtractedValue) external returns (bool) {
        uint256 current = allowance[msg.sender][guy];
        require(current >= subtractedValue, "WMSTC: decrease below zero");
        uint256 updated;
        unchecked {
            updated = current - subtractedValue;
        }
        allowance[msg.sender][guy] = updated;
        emit Approval(msg.sender, guy, updated);
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) public returns (bool) {
        require(dst != address(0), "WMSTC: transfer to zero address");
        require(balanceOf[src] >= wad, "WMSTC: insufficient balance");
        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad, "WMSTC: insufficient allowance");
            allowance[src][msg.sender] -= wad;
        }
        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
        emit Transfer(src, dst, wad);
        return true;
    }
}
