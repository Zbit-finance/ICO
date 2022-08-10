//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./AggregatorV3Interface.sol";

contract ZBIT_ICO is Ownable {
	using SafeMath for uint256;
	mapping(address => bool) private validTokens;
	mapping(address => uint256) private validTokensRate;
	mapping(address => address) private tokensAggregator;

	//Tokens per 1 USD => example rate = 1000000000000000000 wei => means 1USD = 1 Token
	//since our ICO is cross-chain, we can not use a Token/ETH rate as ETH(native token)
	//price differs on different chains
	uint256 public rate = 0;
	bool public saleIsOnGoing = false;
	IERC20 public ZBIT;
	AggregatorV3Interface public ETHPriceAggregator;

	event participatedETH(address indexed sender, uint256 indexed amount);
	event participatedToken(
		address indexed sender,
		uint256 indexed amount,
		address indexed token
	);

	constructor(address _ZBIT, uint256 initialRate) {
		ZBIT = IERC20(_ZBIT);
		rate = initialRate;
		uint256 chainId = getChainID();
		if (chainId == 97) {
			// BSC mainnet
			ETHPriceAggregator = AggregatorV3Interface( // BNB / USD
				0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526
			);
		} else if (chainId == 137) {
			// Polygon Mainnet
			ETHPriceAggregator = AggregatorV3Interface( // MATIC / USD
				0xAB594600376Ec9fD91F8e885dADF0CE036862dE0
			);
		} else if (chainId == 1) {
			//ETH mainnet
			ETHPriceAggregator = AggregatorV3Interface( //ETH / USD
				0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
			);
		}
	}

	modifier notZero(address target) {
		require(target != address(0), "can't use zero address");
		_;
	}

	modifier canTrade() {
		require(saleIsOnGoing == true, "sale is not started yet");
		_;
	}

	//Owner can change ETH pricefeed
	function setETHPriceFeed(address PriceFeed)
		external
		notZero(PriceFeed)
		onlyOwner
	{
		ETHPriceAggregator = AggregatorV3Interface(PriceFeed);
	}

	//to detect which chain we are using
	function getChainID() public view returns (uint256) {
		uint256 id;
		assembly {
			id := chainid()
		}
		return id;
	}

	//ownre can change ZBIT token address
	function setZBITAddress(address _ZBIT) external notZero(_ZBIT) onlyOwner {
		require(_ZBIT != address(ZBIT), "This token is already in use");
		ZBIT = IERC20(_ZBIT);
	}

	//Owner can change ZBIT Rate (enter wei amount)
	function changeZBITRate(uint256 newRate) external onlyOwner {
		rate = newRate;
	}

	//owner must set this to true in order to start ICO
	function setSaleStatus(bool status) external onlyOwner {
		saleIsOnGoing = status;
	}

	function contributeETH() public payable canTrade {
		require(msg.value > 0, "cant contribute 0 eth");
		uint256 toClaim = _ETHToZBIT(msg.value);
		if (ZBIT.balanceOf(address(this)) - toClaim < 0) {
			revert(
				"claim amount is bigger than ICO remaining tokens, try a lower value"
			);
		}
		ZBIT.transfer(msg.sender, toClaim);
		emit participatedETH(msg.sender, msg.value);
	}

	function contributeToken(address token, uint256 amount)
		public
		notZero(token)
		canTrade
	{
		require(validTokens[token], "This token is not allowed for ICO");
		uint256 toClaim = _TokenToZBIT(token, amount);
		if (ZBIT.balanceOf(address(this)) - toClaim < 0) {
			revert(
				"claim amount is bigger than ICO remaining tokens, try a lower value"
			);
		}
		require(IERC20(token).transferFrom(msg.sender, address(this), amount));
		ZBIT.transfer(msg.sender, toClaim);
		emit participatedToken(msg.sender, amount, token);
	}

	//Admin is able to add a costume token here, this tokens are allowed to be contibuted
	//in our ICO

	//aggregator is a contract which gives you latest price of a token
	//not all tokens support aggregators, you can find all aggregator supported tokens
	//in this link https://docs.chain.link/docs/bnb-chain-addresses/
	//Example: we set _token to BTC contract address and aggregator to BTC/USD priceFeed
	function addCostumeTokenByAggregator(address _token, address aggregator)
		public
		notZero(_token)
		notZero(aggregator)
		onlyOwner
	{
		require(_token != address(this), "ZBIT : cant add native token");
		validTokens[_token] = true;
		//amount of tokens per ETH
		tokensAggregator[_token] = aggregator;
	}

	//in this section owner must set a rate (in wei format) for _token
	//this method is not recommended
	function addCostumTokenByRate(address _token, uint256 _rate)
		public
		notZero(_token)
		onlyOwner
	{
		require(_token != address(this), "ZBIT : cant add native token");
		validTokens[_token] = true;
		validTokensRate[_token] = _rate;
	}

	//give rate of a token
	function getCostumeTokenRate(address _token) public view returns (uint256) {
		if (tokensAggregator[_token] == address(0)) {
			return validTokensRate[_token];
		}
		address priceFeed = tokensAggregator[_token];
		(, int256 price, , , ) = AggregatorV3Interface(priceFeed).latestRoundData();
		return uint256(price) * 10**10; //return price in 18 decimals
	}

	//latest price of ETH (native chain token)
	function getLatestETHPrice() public view returns (uint256) {
		(, int256 price, , , ) = ETHPriceAggregator.latestRoundData();
		return uint256(price) * 10**10;
	}

	//Converts ETH(in wei) to ZBIT
	function _ETHToZBIT(uint256 eth) public view returns (uint256) {
		uint256 ethPrice = getLatestETHPrice();
		uint256 EthToUSD = eth.mul(ethPrice);
		return EthToUSD.div(rate);
	}

	//converts Tokens(in wei) to ZBIT
	function _TokenToZBIT(address token, uint256 tokensAmount)
		public
		view
		returns (uint256)
	{
		uint256 _rate = validTokensRate[token];
		if (_rate == 0) {
			_rate = getCostumeTokenRate(token);
		}
		uint256 TokensAmountUSD = _rate.mul(tokensAmount);
		uint256 ZBITAmount = TokensAmountUSD.mul(10**18).div(rate);
		return ZBITAmount.div(10**18);
	}

	function withdrawETH() external onlyOwner {
		payable(msg.sender).transfer(address(this).balance);
	}

	function withdrawTokens(address Token) external onlyOwner {
		IERC20(Token).transfer(msg.sender, IERC20(Token).balanceOf(address(this)));
	}

	//returns balance of contract for a costume token
	function getCostumeTokenBalance(address token)
		external
		view
		returns (uint256)
	{
		return IERC20(token).balanceOf(address(this));
	}

	function getETHBalance() external view returns (uint256) {
		return address(this).balance;
	}

	function ZBITBalance() external view returns (uint256) {
		return ZBIT.balanceOf(address(this));
	}

	//if wallet sent ethereum to this contract sent him back tokens
	receive() external payable {
		uint256 toClaim = _ETHToZBIT(msg.value);
		if (ZBIT.balanceOf(address(this)) - toClaim < 0) {
			revert(
				"claim amount is bigger than ICO remaining tokens, try a lower value"
			);
		}
		ZBIT.transfer(msg.sender, toClaim);
	}
}
