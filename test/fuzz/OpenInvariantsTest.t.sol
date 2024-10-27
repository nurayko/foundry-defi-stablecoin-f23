// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.18;

// import {Test} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// /*
//  * Invariants:
//  * Total supply of DSC < total value of collateral
//  * Getters should never revert
//  */

// contract OpenInvariantsTest is StdInvariant, Test {
//     DeployDSC deployer;
//     DecentralizedStableCoin dsc;
//     DSCEngine dsce;
//     HelperConfig config;
//     address ethUsdPriceFeed;
//     address btcUsdPriceFeed;
//     address weth;
//     address wbtc;
//     function setUp() external {
//         deployer = new DeployDSC();
//         (dsc, dsce, config) = deployer.run();
//         targetContract(address(dsce));
//         (, , weth, wbtc, ) = config.activeNetworkConfig();
//     }

//     function invariant_ProtocolMustHaveMoreValueThanTotalSupply() public view {
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
//         uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

//         uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

//         assert(wethValue + wbtcValue >= totalSupply);
//     }
// }
