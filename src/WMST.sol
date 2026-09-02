// SPDX-License-Identifier: MIT

pragma solidity =0.8.27;

contract WMST {
    string public constant name = "Wrapped MST";
    string public constant symbol = "WMST";
    uint8 public constant decimals = 18;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    uint256 private _totalSupply;

    bool private _locked;

    modifier nonReentrant() {
        require(!_locked, "WMST: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        require(msg.value > 0, "WMST: zero deposit");
        balanceOf[msg.sender] += msg.value;
        _totalSupply += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public nonReentrant {
        require(balanceOf[msg.sender] >= wad, "WMST: insufficient balance");
        balanceOf[msg.sender] -= wad;
        _totalSupply -= wad;
        emit Withdrawal(msg.sender, wad);
        (bool ok, ) = msg.sender.call{value: wad}("");
        require(ok, "WMST: native transfer failed");
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function increaseAllowance(address guy, uint256 addedValue) public returns (bool) {
        uint256 newAllowance = allowance[msg.sender][guy] + addedValue;
        allowance[msg.sender][guy] = newAllowance;
        emit Approval(msg.sender, guy, newAllowance);
        return true;
    }

    function decreaseAllowance(address guy, uint256 subtractedValue) public returns (bool) {
        uint256 currentAllowance = allowance[msg.sender][guy];
        require(currentAllowance >= subtractedValue, "WMST: decreased allowance below zero");
        uint256 newAllowance = currentAllowance - subtractedValue;
        allowance[msg.sender][guy] = newAllowance;
        emit Approval(msg.sender, guy, newAllowance);
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) public returns (bool) {
        require(dst != address(0), "WMST: transfer to zero address");
        require(balanceOf[src] >= wad, "WMST: insufficient balance");
        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad, "WMST: insufficient allowance");
            allowance[src][msg.sender] -= wad;
        }
        balanceOf[src] -= wad;
        balanceOf[dst] += wad;
        emit Transfer(src, dst, wad);
        return true;
    }
}
