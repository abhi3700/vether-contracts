//SPDX-License-Identifier: MIT

pragma solidity >= 0.6.4 <= 0.9.0;

import "hardhat/console.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";

/**
 * @title Vether
 * @author abhi3700
 * @notice Vether contract is used as a mode of investment of ETH & getting back BOOT tokens
 * in return.
 * @dev Using this contract people will be able to send Ethers to this contract &
 * in return receive BOOT tokens.
 * Details:
 *      M-1: 
 *      - to keep the minted public sale tokens in the MainToken contract &
 *      - call MainToken contract's transfer & approve functions on every BOOT distribution 
 *          giveaway inside deposit() function.
 *      - cons: gas will be very high because of calling 2 functions of the MainToken contract.
 *      
 *      M-2:[RECOMMENDED] 
 *      - to manually transfer the minted public sale tokens at once from MainToken to the Vether contract.
 *      - And during each giveaway of BOOT tokens, just update the balanceofPublicSaleTokens on every transfer.
 *      - cons: a balance mapping storage variable has to be maintained so that every BOOT tokens holder's balance 
 *          is stored.
 */

contract Vether5 is ReentrancyGuard {
    using SafeMath for uint256;

    // General constants
    uint256 constant HOUR = 3600;
    uint256 constant DAY = 86400;
    uint256 constant WEEK = 86400 * 7;
    uint256 constant YEAR = WEEK * 52;

    // Supply parameters
    // SEED_ROUND: constant(uint256) = 0
    // PUBLIC_ROUND: constant(uint256) = 1
    // SWERVE_AIRDROP: constant(uint256) = 2
    // DEVFUND_TEAM: constant(uint256) = 3
    // COMMUNITY_LP: constant(uint256) = 4

    // INITIAL_SUPPLY: constant(uint256) = 0
    // INFLATION_DELAY: constant(uint256) = 3 * HOUR # Three Hour delay before minting may begin
    // RATE_DENOMINATOR: constant(uint256) = 10 ** 18
    uint256 constant RATE_TIME = WEEK;                                         // How often the rate goes to the next epoch
    uint256 constant INITIAL_RATE = 2_474_410 * 10 ** 18 / WEEK;                 // 2,474,410 for the first week
    uint256 constant EPOCH_INFLATION = 98_831;                                  // 98.831 % of last week
    uint256 constant LATE_FIX_RATE = 600;                                      // 0.06% total supply
    uint256 constant INITIAL_RATE_EPOCH_CUTTOF = 260;                          // After 260 Weeks use the late rate

    // Supply variables
    uint256 public miningEpoch;
    uint256 public startEpochTime;
    uint256 public rate;

    uint256 startEpochSupply;

    // Events
/*    event NewEra(uint era, uint emission, uint time, uint totalBurnt);
    event NewDay(uint era, uint day, uint time, uint previousDayTotal, uint previousDayMembers);
    event Burn(address indexed payer, address indexed member, uint era, uint day, uint units, uint dailyTotal);
    event Withdrawal(address indexed caller, address indexed member, uint era, uint day, uint value, uint vetherRemaining);
*/    
    event updateMiningParameters(uint256 time, uint256 rate, uint256 supply);
    event Invest(address indexed user, uint256 amountDeposited, uint256 amountReceived);

    address payable public treasuryAddress;
    address payable public mainTokenAddress;

    uint256 rateperETH;             // rate per ETH, calculated inside a function here.
    uint256 public weiRaised;              // amount of wei raised
    IERC20 public token;
    // uint256 public balanceofPublicSaleTokens;           // [OPTIONAL] will be updated by calling setBalancePublicSaleTokens()

    // define all the mining calculations here so that it doesn't have to
    // called from MainToken contract
    constructor(address payable _treasuryAddress, uint256 rateperETH, IERC20 token) {
    // constructor() {
        // require(treasuryAddress != payable(address(0));
        // treasuryAddress = payable(address(0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB));             // testing 
        treasuryAddress = _treasuryAddress;             // all the ETH transfers are stored in this address.
        rateperETH = 10_000;                               // Testing: 1 ETH -> 10,000 BOOT tokens.
    }


    function setMainTokenAddress(address payable _mainTokenAddress) external {
        mainTokenAddress = _mainTokenAddress;
    }

    function deposit() external payable nonReentrant {
        // 0. checks
        require(msg.sender != address(0));

        uint256 weiAmount = msg.value;
        require(weiAmount != 0);
        
        // ------------------------------------------------------------------
        // 1. calculate the BOOT tokens to be transferred for the weiAmount transferred
        uint256 tokens = _getTokenAmount(weiAmount);

        // ------------------------------------------------------------------
        // 2. add the wei amount raised to date
        weiRaised = weiRaised.add(weiAmount);

        // ------------------------------------------------------------------
        // 3. forward weiAmount to treasury address
        // v0.8.6
        (bool success, ) = treasuryAddress.call{value:msg.value}("");               // send ETH to treasuryAddress
        require(success, "Transfer failed.");        

        // v0.6.4
        // treasuryAddress.call.value(msg.value)("");                                 // send ETH to treasuryAddress

        // ------------------------------------------------------------------
        // 4. send BOOT tokens to the ICO participator
        IERC20 tcontract = IERC20(mainTokenAddress);
        // require(tcontract.transferFrom(address(this), msg.sender, tokens), "Don't have enough balance");
        require(tcontract.transfer(msg.sender, tokens), "Don't have enough balance");

        emit Invest(msg.sender, msg.value, tokens);
    }


    /// @notice release of BOOT public sale tokens from this contract 
    /// based on emission rules
    /// @dev updates the rate the mining parameters for public sale tokens
    /// 
    function _updateEmission() private {
        uint256 _rate = rate;
        uint256 _startEpochSupply = startEpochSupply;
        miningEpoch += 1;
        startEpochTime = startEpochTime.add(RATE_TIME);

        if (miningEpoch == 0) {
            _rate = INITIAL_RATE;
        } else {
            _startEpochSupply = _startEpochSupply.add(rate.mul(RATE_TIME));
            if (miningEpoch < INITIAL_RATE_EPOCH_CUTTOF) {
                _rate = _rate.mul(EPOCH_INFLATION).div(100000);
            } else {
                _rate = 0;
            }
        }

        startEpochSupply = _startEpochSupply;
        rate = _rate;
        emit updateMiningParameters(block.timestamp, _rate, _startEpochSupply);
    }

    /**
    * @dev Override to extend the way in which ether is converted to tokens.
    * @param _weiAmount Value in wei to be converted into tokens
    * @return Number of tokens that can be purchased with the specified _weiAmount
    */
    function _getTokenAmount(uint256 _weiAmount) 
            internal view 
            returns (uint256)
    {
        return _weiAmount.mul(rateperETH.div(10**18));
    }

}