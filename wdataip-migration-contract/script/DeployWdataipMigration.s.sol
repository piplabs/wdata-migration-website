// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WdataipMigration} from "../src/WdataipMigration.sol";

/// @notice Deploys WdataipMigration to BSC mainnet or testnet.
/// @dev Reads configuration from the environment:
///      - PRIVATE_KEY      (required) deployer key
///      - OWNER_ADDRESS    (required) initial Ownable2Step owner
///      - WIP_ADDRESS      (optional) defaults to the verified BSC-mainnet wIP address
///      - WDATAIP_ADDRESS  (optional) defaults to the verified BSC-mainnet WDATAIP address
///
///      Mainnet: forge script script/DeployWdataipMigration.s.sol \
///                 --rpc-url bsc --broadcast --verify
///      Testnet: WIP_ADDRESS=0x.. WDATAIP_ADDRESS=0x.. forge script \
///                 script/DeployWdataipMigration.s.sol --rpc-url bsc_testnet --broadcast --verify
contract DeployWdataipMigration is Script {
    address internal constant WIP_MAINNET = 0x4d6394bC3031F751EdcE368C189b0E060b527107;
    address internal constant WDATAIP_MAINNET = 0xA37EDed373c5cdF88644db7C6b89f222e756aFB2;

    function run() external returns (WdataipMigration migration) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        address wip = vm.envOr("WIP_ADDRESS", WIP_MAINNET);
        address wdataip = vm.envOr("WDATAIP_ADDRESS", WDATAIP_MAINNET);

        vm.startBroadcast(deployerKey);
        migration = new WdataipMigration(IERC20(wip), IERC20(wdataip), owner);
        vm.stopBroadcast();

        console2.log("WdataipMigration deployed at:", address(migration));
        console2.log("  wip:    ", wip);
        console2.log("  wdataip:", wdataip);
        console2.log("  owner:  ", owner);
    }
}
