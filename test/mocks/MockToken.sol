// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IPToken} from "@interfaces/IPToken.sol";

contract MockToken is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_)
        ERC20(name, symbol)
    {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockReentrantToken is MockToken {
    constructor(string memory name, string memory symbol, uint8 decimals_)
        MockToken(name, symbol, decimals_)
    {}

    function transferFrom(address, address, uint256) public override returns (bool) {
        IPToken(msg.sender).deposit(0, msg.sender);
        return true;
    }
}

contract MockTestToken is ERC20, Ownable {
    uint256 public mintAmount;
    mapping(address => uint256) public lastMintTimestamp;
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 mintAmount_
    ) ERC20(name, symbol) Ownable(msg.sender) {
        _decimals = decimals_;
        mintAmount = mintAmount_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint() external {
        require(block.timestamp - lastMintTimestamp[msg.sender] > 3600, "cooldown mint");
        lastMintTimestamp[msg.sender] = block.timestamp;
        _mint(msg.sender, mintAmount);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function setMintAmount(uint256 amount) external onlyOwner {
        mintAmount = amount;
    }
}

// MockPToken
contract MockPToken is ERC20 {
    address public immutable asset;
    mapping(address => uint256) public collateralBalances;
    mapping(address => uint256) public borrowBalances;

    constructor(address _asset) ERC20("test", "tst") {
        asset = _asset;
    }

    function deposit(uint256 amount, address account) external returns (uint256) {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        _mint(account, amount);
        collateralBalances[account] += amount;

        return amount;
    }

    function borrowOnBehalfOf(address account, uint256 amount) external {
        borrowBalances[account] += amount;
        MockToken(asset).mint(msg.sender, amount);
    }

    function repayBorrowOnBehalfOf(address account, uint256 amount) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        borrowBalances[account] -= amount;
    }

    function redeem(uint256 amount, address receiver, address account)
        external
        returns (uint256)
    {
        collateralBalances[account] -= amount;
        _burn(account, amount);
        IERC20(asset).transfer(receiver, amount);
        return amount;
    }

    function withdraw(uint256 amount, address receiver, address account)
        external
        returns (uint256)
    {
        collateralBalances[account] -= amount;
        _burn(account, amount);
        IERC20(asset).transfer(receiver, amount);
        return amount;
    }
}
