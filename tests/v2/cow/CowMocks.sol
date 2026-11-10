// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
contract CowTokenMock is ERC20 {
    uint8 public tokenDecimals = 18;
    uint256 public mintBps = 10_000;
    uint256 public tax;
    address public taxFrom;
    address public debitFrom;
    uint256 public extraDebit;
    constructor() ERC20("mock", "MOCK") {}
    function decimals() public view override returns (uint8) {
        return tokenDecimals;
    }
    function setDecimals(uint8 value) external {
        tokenDecimals = value;
    }
    function setMintBps(uint256 value) external {
        mintBps = value;
    }
    function setTax(address from, uint256 value) external {
        taxFrom = from;
        tax = value;
    }
    function setExtraDebit(address from, uint256 value) external {
        debitFrom = from;
        extraDebit = value;
    }
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    function deposit() external payable {
        _mint(msg.sender, (msg.value * mintBps) / 10_000);
    }
    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool ok, ) = msg.sender.call{ value: amount }("");
        require(ok);
    }
    function transfer(address to, uint256 amount) public override returns (bool) {
        super.transfer(to, amount);
        if (msg.sender == taxFrom && tax != 0) _burn(to, tax);
        if (msg.sender == debitFrom && extraDebit != 0) _burn(msg.sender, extraDebit);
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        super.transferFrom(from, to, amount);
        if (from == taxFrom && tax != 0) _burn(to, tax);
        if (from == debitFrom && extraDebit != 0) _burn(from, extraDebit);
        return true;
    }
    receive() external payable {}
}
contract CowSettlementMock {
    address private _relayer;
    bytes32 private _domain = keccak256("test domain");
    mapping(bytes => bool) public signed;
    mapping(bytes => uint256) public filledAmount;
    function setRelayer(address value) external {
        _relayer = value;
    }
    function setDomain(bytes32 value) external {
        _domain = value;
    }
    function vaultRelayer() external view returns (address) {
        return _relayer == address(0) ? address(this) : _relayer;
    }
    function domainSeparator() external view returns (bytes32) {
        return _domain;
    }
    function setPreSignature(bytes calldata uid, bool value) external {
        signed[uid] = value;
    }
    function fill(address escrow, address sell, address bold, uint256 amount, uint256 out) external {
        IERC20(sell).transferFrom(escrow, address(this), amount);
        CowTokenMock(payable(bold)).mint(escrow, out);
    }
}
