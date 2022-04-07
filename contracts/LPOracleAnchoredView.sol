pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;
import "./SafeMath.sol";
import "./dex/IDexPair.sol";

interface OracleERC20 {
	function decimals() external view returns (uint256);
}
interface IStdReference {
    /// A structure returned whenever someone requests for standard reference data.
    struct ReferenceData {
        uint256 rate; // base/quote exchange rate, multiplied by 1e18.
        uint256 lastUpdatedBase; // UNIX epoch of the last time when base price gets updated.
        uint256 lastUpdatedQuote; // UNIX epoch of the last time when quote price gets updated.
    }

    /// Returns the price data for the given base/quote pair. Revert if not available.
    function getReferenceData(string calldata _base, string calldata _quote)
        external
        view
        returns (ReferenceData memory);

    /// Similar to getReferenceData, but with multiple base/quote pairs at once.
    function getReferenceDataBulk(string[] calldata _bases, string[] calldata _quotes)
        external
        view
        returns (ReferenceData[] memory);
}


contract LPOracleAnchoredView {
	using SafeMath for uint;
	IStdReference ref;
	string constant public quote = "USD";

	mapping(string => OracleTokenConfig) CTokenConfigs;
	mapping(address => string) cTokenSymbol;

	struct OracleTokenConfig {
    	address cToken;
    	address underlying;
		address tokenA;
		address tokenB;
    	string  symbol;
		string  symbolA;
		string  symbolB;
    	int256  baseUnit;
	}
	constructor(address _ref,OracleTokenConfig[] memory configs) public {
		ref = IStdReference(_ref);
		for(uint i = 0; i < configs.length; i++){
			OracleTokenConfig memory config = configs[i];
			require(config.baseUnit > 0, "baseUnit must be greater than zero");
			CTokenConfigs[config.symbol] = config;
			cTokenSymbol[config.cToken] = config.symbol;
		}
	}  

	function price(string calldata symbol) external view returns (int256) {
		return priceInternal(symbol);
    }

	function getUnderlyingPrice(address cToken) external view returns (int256) {
		string memory symbol = cTokenSymbol[cToken];
		OracleTokenConfig memory config = CTokenConfigs[symbol];
		int256 rate = priceInternal(symbol);
		return int256div(int256mul(1e28,rate),config.baseUnit);
    }

	function priceInternal(string memory symbol) internal view returns (int256) {
		require(CTokenConfigs[symbol].cToken != address(0),"config not found");
		return getPrice(symbol);
    }

	function oraclePrice(string memory symbol) internal view returns(IStdReference.ReferenceData memory data){
		return ref.getReferenceData(symbol, quote);
	}

	function getPrice(string memory symbol) internal view returns(int256) {
		if(keccak256(abi.encode("ROSE")) == keccak256(abi.encode(symbol))){
			IStdReference.ReferenceData memory data = oraclePrice(symbol);
			return int256(data.rate.div(1e10));	
		}else{
			(uint totalSupply, uint rProduct) = reserveProductAndTotalSupply(symbol);
			uint pProduct = priceProduct(symbol);
			uint p = sqrt(rProduct).mul(sqrt(pProduct)).mul(2).div(totalSupply);
			return int256(p.div(1e10));	
		}
	}

	function reserveProductAndTotalSupply(string memory symbol) internal view returns(uint totalSUpply,uint product) {
		OracleTokenConfig memory config = CTokenConfigs[symbol];
		IDexPair dexPair = IDexPair(config.underlying);
		totalSUpply = dexPair.totalSupply();
		(uint112 reserve0, uint112 reserve1,) = dexPair.getReserves();
		uint decimal0 = OracleERC20(dexPair.token0()).decimals();
		uint decimal1 = OracleERC20(dexPair.token1()).decimals();
		uint amount0 = uint(reserve0).mul(1e18).div(10 ** decimal0);
		uint amount1 = uint(reserve1).mul(1e18).div(10 ** decimal1);
		product = amount0.mul(amount1);
	}

	function priceProduct(string memory symbol) internal view returns(uint product){
		OracleTokenConfig memory config = CTokenConfigs[symbol];
		string memory symbol0;
		string memory symbol1;
		if(config.tokenA < config.tokenB){
			symbol0 = config.symbolA;
			symbol1 = config.symbolB;
		}else{
			symbol0 = config.symbolB;
			symbol1 = config.symbolA;
		}
		uint price0 = oraclePrice(symbol0).rate;
		uint price1 = oraclePrice(symbol1).rate;
		product = price0.mul(price1);
	}


	function int256mul(int256 a, int256 b) internal pure returns (int256) {
   
        if (a == 0) {
            return 0;
        }

        int256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function int256div(int256 a, int256 b) internal pure returns (int256) {
        return int256div(a, b, "SafeMath: division by zero");
    }

    function int256div(int256 a, int256 b, string memory errorMessage) internal pure returns (int256) {

        require(b > 0, errorMessage);
        int256 c = a / b;
    
        return c;
    }

	function sqrt(uint x) internal pure returns (uint) {
    	if (x == 0) return 0;
    	uint xx = x;
    	uint r = 1;

    	if (xx >= 0x100000000000000000000000000000000) {
    	  xx >>= 128;
    	  r <<= 64;
    	}

    	if (xx >= 0x10000000000000000) {
    	  xx >>= 64;
    	  r <<= 32;
    	}
    	if (xx >= 0x100000000) {
    	  xx >>= 32;
    	  r <<= 16;
    	}
    	if (xx >= 0x10000) {
    	  xx >>= 16;
    	  r <<= 8;
    	}
    	if (xx >= 0x100) {
    	  xx >>= 8;
    	  r <<= 4;
    	}
    	if (xx >= 0x10) {
    	  xx >>= 4;
    	  r <<= 2;
    	}
    	if (xx >= 0x8) {
    	  r <<= 1;
    	}

    	r = (r + x / r) >> 1;
    	r = (r + x / r) >> 1;
    	r = (r + x / r) >> 1;
    	r = (r + x / r) >> 1;
    	r = (r + x / r) >> 1;
    	r = (r + x / r) >> 1;
    	r = (r + x / r) >> 1; // Seven iterations should be enough
    	uint r1 = x / r;
    	return (r < r1 ? r : r1);
  }	

}