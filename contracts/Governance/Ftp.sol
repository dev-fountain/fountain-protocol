pragma solidity >=0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract Ftp is ERC20{
    constructor(uint _totalSupply) ERC20("Fountain Protocol","FTP"){
        _mint(msg.sender, _totalSupply);
    }
}
