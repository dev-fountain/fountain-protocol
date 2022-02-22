pragma solidity >=0.8.0;
import "./interface/IComptroller.sol";
contract FTPGuardian {
	event NewGuardian(address oldGuardian,address newGuardian);
	address public owner;
	address public guardian;
	constructor(address _owner,address _guardian){
		require(address(0) != _owner,"invalid address");
		require(address(0) != _guardian,"invalid address");
		owner = _owner;
		guardian = _guardian;
	}

	function setGuardian(address newGuardian) external{
		require(msg.sender == owner,"only owner can call this function");
		require(guardian != newGuardian,"newGuardian can not be same as oldGuardian");
		address oldGuardian = guardian;
		guardian = newGuardian;
		emit NewGuardian(oldGuardian, newGuardian);
	}
	function systemStop(address _unitroller) external {
		require(msg.sender == guardian,"permission deny");
		IComptroller unitroller = IComptroller(_unitroller);
		
		address[] memory ctokens1 = unitroller.getAllMarkets();
		for(uint i = 0; i < ctokens1.length; i++){
			if(!unitroller.mintGuardianPaused(address(ctokens1[i]))){
				unitroller._setMintPaused(ctokens1[i],true);
			}
			if(!unitroller.borrowGuardianPaused(address(ctokens1[i]))){
				unitroller._setBorrowPaused(ctokens1[i],true);
			}
		}
		if(!unitroller.transferGuardianPaused()){
			unitroller._setTransferPaused(true);
		}
		if(!unitroller.seizeGuardianPaused()){
			unitroller._setSeizePaused(true);
		}
	}

}