// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "src/IDO_ETH.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(uint256 initialSupply) ERC20("Mock Token", "MTK") {
        _mint(msg.sender, initialSupply);
    }
}

contract IDO_ETH_PresaleTest is Test {
    IDO_ETH_Persale presale;
    MockERC20 token;
    address owner = address(this);
    address user1 = address(0x123);
    address user2 = address(0x245);
    address Foundation = 0x9753473c77316AdF25C839Ec44C2121F9266cAAE;

    IDO_ETH_Persale.PresaleOptions options;

    function setUp() public {
        // Mock token with an initial supply
        token = new MockERC20(100000 * 10 ** 18);

        // Presale options
        options = IDO_ETH_Persale.PresaleOptions({
            tokenprice: 10000,
            tokenDeposit: 20000 * 10 ** 18,
            hardCap: 0.5 ether,
            softCap: 0.2 ether,
            max: 0.1 ether,
            min: 0.01 ether,
            start: uint112(block.timestamp),
            end: uint112(block.timestamp + 3 minutes)
        });

        // Initialize presale contract
        presale = new IDO_ETH_Persale(address(token), options);

        vm.prank(owner);
        // approve tokens to the presale contract
        token.approve(address(presale), options.tokenDeposit);
        // vm.prank(owner);
        // // Transfer tokens to presale contract for the sale
        // token.transfer(address(presale), options.tokenDeposit);
    }

    function testPresaleInitialization() public {
        (
            IERC20 token,
            uint256 tokenBalance,
            uint256 tokensClaimable,
            uint256 ETHRaised,
            uint8 state,
            IDO_ETH_Persale.PresaleOptions memory options
        ) = presale.pool();
        assertEq(state, 1, "Presale should be initialized.");
        assertEq(tokenBalance, 0, "Token balance should be zero at start.");
    }

    function testDepositTokens() public {
        vm.prank(owner);
        presale.deposit();

        (
            IERC20 token,
            uint256 tokenBalance,
            uint256 tokensClaimable,
            uint256 ETHRaised,
            uint8 state,
            IDO_ETH_Persale.PresaleOptions memory options
        ) = presale.pool();

        assertEq(state, 2, "Presale should be active.");
        assertEq(tokenBalance, options.tokenDeposit, "Token balance should match the deposited amount.");
    }

    function testPurchaseTokens() public {
        vm.startPrank(owner);
        presale.deposit();
        vm.stopPrank();

        // User 1 participates in presale with minimum contribution
        vm.deal(user1, 1 ether);
        vm.prank(user1);

        (bool success,) = address(presale).call{value: 0.01 ether}("");
        require(success, "Purchase failed");
        (
            IERC20 token,
            uint256 tokenBalance,
            uint256 tokensClaimable,
            uint256 ETHRaised,
            uint8 state,
            IDO_ETH_Persale.PresaleOptions memory options
        ) = presale.pool();

        assertEq(presale.contributions(user1), 0.01 ether, "User1's contribution should be recorded.");
        assertEq(ETHRaised, 0.01 ether, "ETH raised should be updated.");
    }

    function testRefundOnUnsuccessfulPresale() public {
        vm.startPrank(owner);
        presale.deposit();
        vm.stopPrank();

        // User 1 and User 2 participate but total ETH raised does not meet softCap
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        address(presale).call{value: 0.1 ether}("");

        vm.deal(user2, 1 ether);
        vm.prank(user2);
        address(presale).call{value: 0.05 ether}("");

        // Move time forward to end of presale period
        vm.warp(block.timestamp + 1 weeks);

        // Owner cancels presale
        vm.startPrank(owner);
        presale.cancel();
        // presale.updatastate();
        vm.stopPrank();

        (
            IERC20 token,
            uint256 tokenBalance,
            uint256 tokensClaimable,
            uint256 ETHRaised,
            uint8 state,
            IDO_ETH_Persale.PresaleOptions memory options
        ) = presale.pool();

        // Users can now refund their ETH
        vm.prank(user1);
        presale._withdrawALLForPresale_user();
        assertEq(user1.balance, 1 ether, "User1 should receive a refund.");

        vm.prank(user2);
        presale._withdrawALLForPresale_user();
        assertEq(user2.balance, 1 ether, "User2 should receive a refund.");
    }

    function testSuccessfulPresale() public {
        vm.startPrank(owner);
        presale.deposit();
        vm.stopPrank();

        // User 1 and User 2 contribute to meet softCap
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        address(presale).call{value: 0.1 ether}("");

        vm.deal(user2, 1 ether);
        vm.prank(user2);
        address(presale).call{value: 0.1 ether}("");

        // Move time forward to end of presale period
        vm.warp(block.timestamp + 1 weeks);

        // Finalize the presale
        vm.prank(owner);
        presale.updatastate();

        (
            IERC20 token,
            uint256 tokenBalance,
            uint256 tokensClaimable,
            uint256 ETHRaised,
            uint8 state,
            IDO_ETH_Persale.PresaleOptions memory options
        ) = presale.pool();

        uint256 tokensClaimable1 = presale.userTokens(user1);
        uint256 tokensClaimable2 = presale.userTokens(user2);

        // User claims tokens
        vm.prank(user1);
        presale._withdrawForPresale(tokensClaimable1);
        assertEq(token.balanceOf(user1), tokensClaimable1, "User1 should receive their allocated tokens.");

        // Owner withdraws ETH raised
        uint256 ethRaised = ETHRaised;
        vm.prank(owner);
        presale._withdrawALLForPresale_owner();
        assertEq(Foundation.balance, ethRaised, "Owner should receive the ETH raised.");
    }
}
