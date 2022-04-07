pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;
import "./SafeMath.sol";
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


contract OracleAnchoredView {
	using SafeMath for uint;
	IStdReference ref;
	string constant public quote = "USD";

	mapping(string => OracleTokenConfig) CTokenConfigs;
	mapping(address => string) cTokenSymbol;

	struct OracleTokenConfig {
    	address cToken;
    	address underlying;
    	string  symbol;
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

	function priceInternal(string memory symbol) internal view returns (int256) {
		require(CTokenConfigs[symbol].cToken != address(0),"config not found");
		IStdReference.ReferenceData memory data =  ref.getReferenceData(symbol, quote);
		require(data.rate > 0,"price can not be 0");
		// return int256(data.rate).div(1e10);
		return int256(data.rate.div(1e10));
    }

	function getUnderlyingPrice(address cToken) external view returns (int256) {
		string memory symbol = cTokenSymbol[cToken];
		OracleTokenConfig memory config = CTokenConfigs[symbol];
		int256 rate = priceInternal(symbol);
		// return 1e28 * rate / config.baseUnit;
		return int256div(int256mul(1e28,rate),config.baseUnit);
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


}