// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {SwipeDonation} from "../src/SwipeDonation.sol";
import {BetaDonationPool} from "../src/BetaDonationPool.sol";

/**
 * @title Deploy
 * @notice Deploys SwipePad contracts to Celo or Base
 * @dev Run with:
 *      Celo:   forge script script/Deploy.s.sol --rpc-url $CELO_RPC --broadcast --verify
 *      Base:   forge script script/Deploy.s.sol --rpc-url $BASE_RPC --broadcast --verify
 *      Local:  PRIVATE_KEY=0x... forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
 */
contract Deploy is Script {
    // Multisig addresses for ownership (update before mainnet deployment)
    address constant CELO_MULTISIG = address(0); // Set via env if needed
    address constant BASE_MULTISIG = address(0); // Set via env if needed

    // Token addresses
    address constant CELO_CUSD = 0x765DE816845861e75A25fCA122bb6898B8B1282a;
    address constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // Beta pool config
    uint256 constant MAX_CREDITS_PER_USER = 25 * 1e16; // 0.25 cUSD/USDC (25 swipes @ $0.01)
    uint256 constant MIN_DONATION_AMOUNT = 1e16; // $0.01 minimum

    function run() public {
        uint256 chainId = block.chainid;
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address owner = getOwnerForChain(chainId, deployer);
        address token = getTokenForChain(chainId);
        address envOwner = vm.envOr("OWNER_ADDRESS", address(0));
        address envToken = vm.envOr("TOKEN_ADDRESS", address(0));
        uint256 maxCredits = vm.envOr("MAX_CREDITS_PER_USER", MAX_CREDITS_PER_USER);
        uint256 minDonation = vm.envOr("MIN_DONATION_AMOUNT", MIN_DONATION_AMOUNT);

        if (envOwner != address(0)) {
            owner = envOwner;
        }
        if (envToken != address(0)) {
            token = envToken;
        }

        require(owner != address(0), "Owner not configured for this chain");
        require(token != address(0), "Token not configured for this chain");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy SwipeDonation (for post-beta direct donations)
        SwipeDonation donation = new SwipeDonation(owner);

        // Deploy BetaDonationPool (for beta with on-chain credits)
        BetaDonationPool pool = new BetaDonationPool(
            token,
            owner,
            maxCredits,
            minDonation
        );

        vm.stopBroadcast();

        console.log("=== SwipePad Contracts Deployed ===");
        console.log("Chain ID:", chainId);
        console.log("Owner:", owner);
        console.log("");
        console.log("SwipeDonation:", address(donation));
        console.log("BetaDonationPool:", address(pool));
        console.log("  Token:", token);
        console.log("  Max Credits/User:", maxCredits);
        console.log("  Min Donation:", minDonation);

        string memory json = vm.serializeAddress("contracts", "SwipeDonation", address(donation));
        json = vm.serializeAddress("contracts", "BetaDonationPool", address(pool));
        json = vm.serializeAddress("config", "owner", owner);
        json = vm.serializeAddress("config", "token", token);
        json = vm.serializeUint("config", "chainId", chainId);
        json = vm.serializeUint("config", "maxCreditsPerUser", maxCredits);
        json = vm.serializeUint("config", "minDonationAmount", minDonation);

        string memory outPath = string.concat("deployments/", vm.toString(chainId), ".json");
        vm.writeJson(json, outPath);
        console.log("Deployment JSON:", outPath);
    }

    function getOwnerForChain(uint256 chainId, address deployer) internal view returns (address) {
        if (chainId == 42220) return vm.envOr("CELO_MULTISIG", CELO_MULTISIG); // Celo Mainnet
        if (chainId == 8453) return vm.envOr("BASE_MULTISIG", BASE_MULTISIG); // Base Mainnet
        if (chainId == 44787) return deployer; // Celo Alfajores
        if (chainId == 84532) return deployer; // Base Sepolia
        if (chainId == 31337) return deployer; // Anvil
        return address(0);
    }

    function getTokenForChain(uint256 chainId) internal pure returns (address) {
        if (chainId == 42220 || chainId == 44787) return CELO_CUSD; // Celo
        if (chainId == 8453 || chainId == 84532) return BASE_USDC; // Base
        if (chainId == 31337) return address(1); // Anvil placeholder (use mock)
        return address(0);
    }
}
