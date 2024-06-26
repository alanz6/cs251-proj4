// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import './token.sol';
import "hardhat/console.sol";


contract TokenExchange is Ownable {
    string public exchange_name = 'MyExchange';

    address tokenAddr = 0x5FbDB2315678afecb367f032d93F642f64180aa3;                                  // TODO: paste token contract address here
    Token public token = Token(tokenAddr);                                

    // Liquidity pool for the exchange
    uint private token_reserves = 0; //currency B
    uint private eth_reserves = 0; //currency A

    mapping(address => uint) private lps;  //store numerators, denomiator is 1000
     
    // Needed for looping through the keys of the lps mapping
    address[] private lp_providers;                     

    // liquidity rewards
    uint private swap_fee_numerator = 5;                // TODO Part 5: Set liquidity providers' returns.
    uint private swap_fee_denominator = 100;

    // Constant: x * y = k
    uint private k;

    constructor() {}
    

    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    function createPool(uint amountTokens)
        external
        payable
        onlyOwner
    {
        // This function is already implemented for you; no changes needed.

        // require pool does not yet exist:
        require (token_reserves == 0, "Token reserves was not 0");
        require (eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require (msg.value > 0, "Need eth to create pool.");
        uint tokenSupply = token.balanceOf(msg.sender);
        require(amountTokens <= tokenSupply, "Not have enough tokens to create the pool");
        require (amountTokens > 0, "Need tokens to create pool.");

        token.transferFrom(msg.sender, address(this), amountTokens);
        token_reserves = token.balanceOf(address(this));
        eth_reserves = msg.value;
        k = token_reserves * eth_reserves;
    }

    // Function removeLP: removes a liquidity provider from the list.
    // This function also removes the gap left over from simply running "delete".
    function removeLP(uint index) private {
        require(index < lp_providers.length, "specified index is larger than the number of lps");
        lp_providers[index] = lp_providers[lp_providers.length - 1];
        lp_providers.pop();
    }

    // Function getSwapFee: Returns the current swap fee ratio to the client.
    function getSwapFee() public view returns (uint, uint) {
        return (swap_fee_numerator, swap_fee_denominator);
    }

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================
    
    /* ========================= Liquidity Provider Functions =========================  */ 

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value).
    // You can change the inputs, or the scope of your function, as needed.
    function addLiquidity(uint max_exchange_rate, uint min_exchange_rate) 
        external 
        payable
    {
        uint exchange_rate = 1000 * token_reserves / eth_reserves; //y/x, price of ETH in terms of token
        require(exchange_rate <= max_exchange_rate);
        require(exchange_rate >= min_exchange_rate);

        uint tokenAmount = msg.value * exchange_rate / 1000; 
        require(token.balanceOf(msg.sender) >= tokenAmount);
        token.transferFrom(msg.sender, address(this), tokenAmount);
        eth_reserves += msg.value;
        token_reserves += tokenAmount;

        bool newProvider = true;
        for (uint i = 0; i < lp_providers.length; i++){
            if(lp_providers[i] != msg.sender) {
                lps[lp_providers[i]] = lps[lp_providers[i]] * (token_reserves - tokenAmount) / token_reserves;
            } else {
                newProvider = false;
            }
        }

        lps[msg.sender] = 1000 * tokenAmount / token_reserves + lps[msg.sender] * (token_reserves - tokenAmount) / token_reserves;
        k = address(this).balance * token.balanceOf(address(this));
        if (newProvider == true) {
            lp_providers.push(msg.sender);
        }
    }

    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint amountETH, uint max_exchange_rate, uint min_exchange_rate)
        public 
        payable
    {   
        require(amountETH < eth_reserves);
        require(amountETH * 1000 <= lps[msg.sender] * eth_reserves);

        uint exchange_rate = 1000 * token_reserves / eth_reserves; //y/x, price of ETH in terms of token
        require(exchange_rate <= max_exchange_rate);
        require(exchange_rate >= min_exchange_rate);

        uint tokenAmount = amountETH * exchange_rate / 1000; 
        require(tokenAmount < token_reserves);
        require(tokenAmount * 1000 <= lps[msg.sender] * token_reserves);
        token.transfer(msg.sender, tokenAmount);
        payable(msg.sender).transfer(amountETH);
        eth_reserves -= amountETH;
        token_reserves -= tokenAmount;

        uint callerIndex = 0;
        for (uint i = 0; i < lp_providers.length; i++){
            if(lp_providers[i] != msg.sender) {
                lps[lp_providers[i]] = lps[lp_providers[i]] * token_reserves / (token_reserves - tokenAmount);
            } else {
                callerIndex = i;
            }
        }
        
        lps[msg.sender] = (lps[msg.sender] * (token_reserves + tokenAmount) - tokenAmount * 1000) / token_reserves;
        k = address(this).balance * token.balanceOf(address(this));
        if (lps[msg.sender] == 0) {
            removeLP(callerIndex);
        }
    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity(uint max_exchange_rate, uint min_exchange_rate)
        external
        payable
    {
        // require (lps[msg.sender] * eth_reserves / 1000 >= 1, "ETH liquidity less than 1");
        removeLiquidity(lps[msg.sender] * eth_reserves / 1000, max_exchange_rate, min_exchange_rate);
    }
    /***  Define additional functions for liquidity fees here as needed ***/


    /* ========================= Swap Functions =========================  */ 

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTokens, uint max_exchange_rate)
        external 
        payable
    {
        require(1000 * token_reserves / eth_reserves <= max_exchange_rate);

        uint exchange_rate = 1000 * eth_reserves / token_reserves; //x/y, price of token in terms of ETH
        uint amountETH = amountTokens * exchange_rate / 1000 * (swap_fee_denominator - swap_fee_numerator) / swap_fee_denominator;
        require(token.balanceOf(msg.sender) >= amountTokens);
        require(amountETH < eth_reserves);
        payable(msg.sender).transfer(amountETH);
        token.transferFrom(msg.sender, address(this), amountTokens);
        eth_reserves -= amountETH;
        token_reserves += amountTokens;
    }



    // Function swapETHForTokens: Swaps ETH for your tokens
    // ETH is sent to contract as msg.value
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint max_exchange_rate)
        external
        payable 
    {
        require(1000 * eth_reserves / token_reserves <= max_exchange_rate);

        uint exchange_rate = 1000 * token_reserves / eth_reserves; //y/x, price of ETH in terms of token
        uint amountTokens = msg.value * exchange_rate / 1000 * (swap_fee_denominator - swap_fee_numerator) / swap_fee_denominator;
        require(amountTokens < token_reserves);
        token.transfer(msg.sender, amountTokens);
        eth_reserves += msg.value;
        token_reserves -= amountTokens;
    }
}
