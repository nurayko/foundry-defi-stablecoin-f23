// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , ) = config
            .activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
    }

    // Constructor tests
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenDontMatch() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressessMustMatch
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    // Price tests
    function testGetUsdValues() public view {
        uint256 ethAmount = 15e18;
        // 15 eth * 2000/ETH = 30 000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(expectedWeth, actualWeth);
    }

    function testGetPriceForToken() public {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 priceForWeth = dsce.getPriceForToken(weth);
        assertEq(priceForWeth, uint256(ethUsdUpdatedPrice));
    }

    // Deposit Collateral

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), COLLATERAL_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            COLLATERAL_AMOUNT
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), COLLATERAL_AMOUNT);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), COLLATERAL_AMOUNT);
        dsce.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier liquidatedSetup() {
        uint256 amountToMint = 100 ether;
        uint256 collateralToCover = 20 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), COLLATERAL_AMOUNT);
        dsce.depositCollateralAndMintDsc(weth, COLLATERAL_AMOUNT, amountToMint);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // deposit tokens to LIQUIDATOR
        ERC20Mock(weth).mint(LIQUIDATOR, collateralToCover);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);
        dsc.approve(address(dsce), amountToMint);
        dsce.liquidate(weth, USER, amountToMint); // We are covering USER's whole debt
        vm.stopPrank();
        _;
    }

    function testCanLiquidate() public liquidatedSetup {}

    function testCanDepositCollateralAndGetAccInfo()
        public
        depositedCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValuesInUsd) = dsce
            .getAccountInformation(USER);
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(
            weth,
            collateralValuesInUsd
        );
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositedAmount, COLLATERAL_AMOUNT);
    }

    function testLiquidateRevertsIfHealthIsOk() public depositedCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsOk.selector);
        dsce.liquidate(weth, USER, COLLATERAL_AMOUNT);
    }

    function testMintDsc() public depositedCollateral {
        vm.startPrank(USER);
        dsce.mintDsc(0.01 ether);
        vm.stopPrank();
        (uint256 totalDscMinted, uint256 collateralValuesInUsd) = dsce
            .getAccountInformation(USER);
        assertEq(totalDscMinted, 0.01 ether);
        console.log(collateralValuesInUsd);
    }

    function testCantRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateral {
        uint256 amountToRedeem = 1000;
        vm.startPrank(USER);
        dsce.redeemCollateral(weth, amountToRedeem);
        vm.stopPrank();
    }

    function testCanRedeemBreakHealthFactor() public depositedCollateral {
        vm.startPrank(USER);
        dsce.mintDsc(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                0
            )
        );
        dsce.redeemCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testMintDscExpectRevertBreakHealthFactor() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                0
            )
        );
        dsce.mintDsc(1);
    }

    function testDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), COLLATERAL_AMOUNT);
        dsce.depositCollateralAndMintDsc(
            weth,
            COLLATERAL_AMOUNT,
            COLLATERAL_AMOUNT / 2
        );
        vm.stopPrank();
    }

    function testGetHealthStatus() public view {
        uint256 healthFactor = dsce.getHealthFactor(msg.sender);
        assertEq(healthFactor, type(uint256).max);
    }

    function testGetCollateralBalanceOfUser() public depositedCollateral {
        uint256 collateralBalanceOfUser = dsce.getCollateralBalanceOfUser(
            USER,
            address(weth)
        );
        assertEq(collateralBalanceOfUser, COLLATERAL_AMOUNT);

        uint256 collateralBalanceOfCurrentUser = dsce
            .getCollateralBalanceOfUser(msg.sender, address(weth));

        assertEq(collateralBalanceOfCurrentUser, 0);
    }

    function testBurnDscSuccess() public {
        uint256 amountToMint = 500;
        uint256 amountToDepositEth = 100;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), COLLATERAL_AMOUNT);
        dsce.depositCollateralAndMintDsc(
            weth,
            amountToDepositEth,
            amountToMint
        );
        dsc.approve(address(dsce), amountToMint);
        dsce.burnDsc(amountToMint);
        vm.stopPrank();

        uint256 balance = dsc.balanceOf(USER);
        assertEq(balance, 0);
    }

    function testBurnDscRevertsWhenZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
    }
}
