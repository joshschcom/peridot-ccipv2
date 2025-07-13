// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../contracts/PeridottrollerG7.sol";
import "../contracts/Unitroller.sol";
import "../contracts/PriceOracle.sol";

/**
 * @title RedeployPeridottrollerFixed
 * @dev Redeploys PeridottrollerG7 with correct PERIDOT token assignment
 *
 * This script addresses the proxy storage layout issue where PERIDOT shows as 0x000...
 *
 * The issue: PeridottrollerG7 sets PERIDOT in constructor, but when accessed through
 * Unitroller proxy, it reads from wrong storage slot.
 *
 * Usage: forge script script/RedeployPeridottrollerFixed.s.sol:RedeployPeridottrollerFixed --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
 */
contract RedeployPeridottrollerFixed is Script {
    // === CONFIGURATION ===
    // Your actual deployed addresses
    address constant EXISTING_UNITROLLER =
        0xa41D586530BC7BC872095950aE03a780d5114445; // Your existing Unitroller proxy address
    address constant ORACLE_ADDRESS =
        0xeAEdaF63CbC1d00cB6C14B5c4DE161d68b7C63A0; // Your SimplePriceOracle
    address constant PERIDOT_ADDRESS =
        0x28fE679719e740D15FC60325416bB43eAc50cD15; // Your Peridot token

    // Same values as original deployment
    uint constant closeFactorMantissa = 0.5e18; // 50%
    uint constant liquidationIncentiveMantissa = 1.08e18; // 8% bonus

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Redeploying PeridottrollerG7 with Fixed PERIDOT ===");
        console.log("Deployer:", deployer);
        console.log("Existing Unitroller:", EXISTING_UNITROLLER);
        console.log("PERIDOT Token:", PERIDOT_ADDRESS);
        console.log("Oracle:", ORACLE_ADDRESS);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Check current state
        Unitroller unitroller = Unitroller(payable(EXISTING_UNITROLLER));
        PeridottrollerG7 currentProxy = PeridottrollerG7(EXISTING_UNITROLLER);

        console.log("\n=== Current State ===");
        console.log("Unitroller Admin:", unitroller.admin());
        console.log(
            "Current Implementation:",
            unitroller.peridottrollerImplementation()
        );
        console.log(
            "Current PERIDOT (via proxy):",
            currentProxy.getPeridotAddress()
        );

        // Verify deployer is admin
        require(
            unitroller.admin() == deployer,
            "Deployer must be Unitroller admin"
        );

        // 2. Deploy new PeridottrollerG7 implementation with correct PERIDOT
        console.log("\n=== Deploying New Implementation ===");
        PeridottrollerG7 newImpl = new PeridottrollerG7(PERIDOT_ADDRESS);
        console.log("New PeridottrollerG7 deployed at:", address(newImpl));
        console.log("New Implementation PERIDOT:", newImpl.getPeridotAddress());

        // 3. Set the new implementation
        console.log("\n=== Updating Unitroller Implementation ===");
        uint setPendingResult = unitroller._setPendingImplementation(
            address(newImpl)
        );
        require(setPendingResult == 0, "Failed to set pending implementation");
        console.log("Pending implementation set");

        // 4. Accept the implementation from the new contract
        newImpl._become(unitroller);
        console.log("New implementation accepted");

        // 5. Verify the update worked
        console.log("\n=== Verification ===");
        console.log(
            "New Implementation Address:",
            unitroller.peridottrollerImplementation()
        );
        console.log("PERIDOT via proxy:", currentProxy.getPeridotAddress());

        // 6. Re-initialize critical settings (they should be preserved, but let's verify)
        console.log("\n=== Verifying Settings ===");
        console.log("Close Factor:", currentProxy.closeFactorMantissa());
        console.log(
            "Liquidation Incentive:",
            currentProxy.liquidationIncentiveMantissa()
        );
        console.log("Price Oracle:", address(currentProxy.oracle()));

        // 7. If PERIDOT is still 0x000..., we have a storage layout issue
        address peridotViaProxy = currentProxy.getPeridotAddress();
        if (peridotViaProxy == address(0)) {
            console.log("\n!!! STORAGE LAYOUT ISSUE CONFIRMED !!!");
            console.log("PERIDOT address is still 0x000... via proxy");
            console.log("This is a fundamental proxy storage layout mismatch");
            console.log("\nPossible solutions:");
            console.log("1. Add a setter function to PeridottrollerG7");
            console.log("2. Deploy a new Unitroller + PeridottrollerG7 pair");
            console.log(
                "3. Create a custom implementation with storage layout fix"
            );
        } else {
            console.log(
                "\n SUCCESS! PERIDOT correctly set to:",
                peridotViaProxy
            );
        }

        vm.stopBroadcast();

        console.log("\n=== Summary ===");
        console.log("Unitroller (Proxy):", EXISTING_UNITROLLER);
        console.log("New PeridottrollerG7:", address(newImpl));
        console.log("Expected PERIDOT:", PERIDOT_ADDRESS);
        console.log("Actual PERIDOT (via proxy):", peridotViaProxy);

        if (peridotViaProxy != PERIDOT_ADDRESS) {
            console.log("\n  NEXT STEPS REQUIRED:");
            console.log("Run the StorageLayoutFix script to resolve the issue");
        }
    }
}
