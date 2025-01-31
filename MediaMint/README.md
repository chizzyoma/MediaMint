# MediaMint Digital Asset Platform

## Overview

MediaMint is a decentralized digital asset management platform built on the Stacks blockchain. It enables content creators to monetize their digital assets through flexible licensing models, including single purchases and tiered subscriptions.

## Key Features

- 🚀 Multiple Asset Licensing Options
  - Single purchase
  - Tiered licensing (Basic, Premium, Enterprise)
  - Subscription-based access

- 💰 Revenue Sharing
  - Configurable creator revenue percentage
  - Transparent platform commission (default 5%)
  - Automatic earnings distribution

- 🔒 License Management
  - Tracks asset ownership
  - Supports time-limited subscriptions
  - Verifiable asset access

## Contract Functions

### Asset Management
- `register_digital_asset`: Create and register a new digital asset
- `configure_asset_licensing_tiers`: Set up different pricing tiers for an asset
- `purchase_digital_asset`: Buy a standard license for an asset
- `purchase_license_tier`: Purchase a specific license tier

### Creator Functions
- `withdraw_creator_earnings`: Withdraw accumulated earnings
- `get_creator_current_balance`: Check current earnings balance

### Read-Only Functions
- `get_digital_asset_details`: Retrieve asset information
- `get_user_asset_license_details`: Check user's license status
- `verify_asset_access`: Validate current asset access

### Administrative Functions
- `update_platform_commission_rate`: Adjust platform commission
- `transfer_platform_administrator`: Change platform administrator

## Error Handling

The contract includes comprehensive error codes for various scenarios:
- Unauthorized actions
- Invalid pricing
- Asset ownership conflicts
- Subscription management
- License tier validation

## Usage Example

```clarity
;; Register a digital asset
(register_digital_asset 
  u1                      ;; Asset identifier
  u1000                   ;; Purchase price (100 STX)
  u750                    ;; Creator revenue percentage (75%)
  "ipfs://asset-metadata" ;; Metadata URI
  true                    ;; Supports subscription
  u144                    ;; Subscription duration (24 hours)
)

;; Configure license tiers
(configure_asset_licensing_tiers
  u1                      ;; Asset identifier
  u500                    ;; Basic tier price
  u1000                   ;; Premium tier price
  u2000                   ;; Enterprise tier price
)

;; Purchase a specific license tier
(purchase_license_tier 
  u1                      ;; Asset identifier
  "premium"               ;; Selected tier
)
```

## Security Considerations

- Only asset creators can configure licensing tiers
- Platform administrator has limited control
- Transparent revenue distribution
- Built-in access verification

## Deployment Requirements

- Stacks blockchain
- Clarity smart contract support
- Minimum Stacks wallet balance for transactions

