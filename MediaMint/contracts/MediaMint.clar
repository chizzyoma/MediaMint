;; MediaMintContract - Digital Asset Platform
;; Enables creators to monetize digital assets through subscriptions and individual purchases

;; Error Codes
(define-constant ERROR_UNAUTHORIZED (err u1))
(define-constant ERROR_INVALID_PRICING (err u2))
(define-constant ERROR_ASSET_ALREADY_OWNED (err u3))
(define-constant ERROR_DIGITAL_ASSET_NOT_FOUND (err u4))
(define-constant ERROR_INSUFFICIENT_PAYMENT (err u5))
(define-constant ERROR_SUBSCRIPTION_EXPIRED (err u6))
(define-constant ERROR_INVALID_SUBSCRIPTION_TERMS (err u7))
(define-constant ERROR_INVALID_DIGITAL_ASSET_ID (err u8))
(define-constant ERROR_INVALID_METADATA_URI (err u9))
(define-constant ERROR_INVALID_ADMIN_ADDRESS (err u10))
(define-constant ERROR_INVALID_LICENSE_TIER (err u11))
(define-constant ERROR_TIER_NOT_CONFIGURED (err u12))

;; Platform Configuration
(define-data-var platform_administrator principal tx-sender)
(define-data-var platform_commission_rate uint u50) ;; 5% platform fee (base 1000)

;; Data Mappings
(define-map digital_asset_registry
    { asset_identifier: uint }
    {
        content_creator: principal,
        purchase_price: uint,
        creator_revenue_percentage: uint,
        content_metadata_uri: (string-utf8 256),
        supports_subscription: bool,
        subscription_period_blocks: uint
    }
)

;; New map for license tiers
(define-map asset_licensing_tiers
    { asset_identifier: uint }
    {
        basic_license_price: uint,
        premium_license_price: uint,
        enterprise_license_price: uint
    }
)

;; User asset licenses map - extended to include tier information
(define-map user_asset_licenses
    { license_holder: principal, asset_identifier: uint }
    {
        acquisition_block_height: uint,
        subscription_expiration_block: uint,
        license_active: bool,
        license_tier: (string-ascii 20)
    }
)

(define-map creator_earnings
    { content_creator: principal }
    { accumulated_balance: uint }
)

;; Private Utility Functions
(define-private (calculate_revenue_distribution (total_revenue uint))
    (let
        (
            (platform_revenue (/ (* total_revenue (var-get platform_commission_rate)) u1000))
        )
        {
            platform_share: platform_revenue,
            creator_share: (- total_revenue platform_revenue)
        }
    )
)

(define-private (transfer_stx_funds (payment_amount uint) (payment_recipient principal))
    (stx-transfer? payment_amount tx-sender payment_recipient)
)

(define-private (is_license_currently_valid (user principal) (asset_identifier uint))
    (match (map-get? user_asset_licenses { license_holder: user, asset_identifier: asset_identifier })
        current_license (and
            (get license_active current_license)
            (<= stacks-block-height (get subscription_expiration_block current_license))
        )
        false
    )
)

;; Public Asset Management Functions
(define-public (register_digital_asset 
                (asset_identifier uint) 
                (asset_price uint) 
                (creator_revenue_share uint) 
                (asset_metadata_uri (string-utf8 256)) 
                (enable_subscription bool) 
                (subscription_duration uint))
    (begin
        (asserts! (> asset_identifier u0) ERROR_INVALID_DIGITAL_ASSET_ID)
        (asserts! (> asset_price u0) ERROR_INVALID_PRICING)
        (asserts! (and (>= creator_revenue_share u0) (<= creator_revenue_share u1000)) ERROR_INVALID_PRICING)
        (asserts! (> (len asset_metadata_uri) u0) ERROR_INVALID_METADATA_URI)
        (asserts! (or (not enable_subscription) (> subscription_duration u0)) ERROR_INVALID_SUBSCRIPTION_TERMS)
        
        (map-set digital_asset_registry
            { asset_identifier: asset_identifier }
            {
                content_creator: tx-sender,
                purchase_price: asset_price,
                creator_revenue_percentage: creator_revenue_share,
                content_metadata_uri: asset_metadata_uri,
                supports_subscription: enable_subscription,
                subscription_period_blocks: subscription_duration
            }
        )
        (ok true)
    )
)

;; New function to configure license tiers for an asset
(define-public (configure_asset_licensing_tiers 
    (asset_identifier uint)
    (basic_price uint)
    (premium_price uint)
    (enterprise_price uint))
    (begin
        ;; Validate that the asset exists
        (asserts! (> asset_identifier u0) ERROR_INVALID_DIGITAL_ASSET_ID)
        (unwrap! (map-get? digital_asset_registry { asset_identifier: asset_identifier }) ERROR_DIGITAL_ASSET_NOT_FOUND)
        
        ;; Ensure the caller is the asset creator
        (asserts! (is-eq tx-sender 
            (unwrap-panic (get content_creator (map-get? digital_asset_registry { asset_identifier: asset_identifier }))))
            ERROR_UNAUTHORIZED)
        
        ;; Validate prices
        (asserts! (and 
            (> basic_price u0) 
            (> premium_price basic_price) 
            (> enterprise_price premium_price)) 
            ERROR_INVALID_PRICING)
        
        ;; Set license tiers
        (map-set asset_licensing_tiers
            { asset_identifier: asset_identifier }
            {
                basic_license_price: basic_price,
                premium_license_price: premium_price,
                enterprise_license_price: enterprise_price
            }
        )
        
        (ok true)
    )
)

;; Modified purchase function to support license tiers
(define-public (purchase_license_tier 
    (asset_identifier uint) 
    (tier (string-ascii 20)))
    (let
        (
            ;; Validate asset identifier
            (digital_asset (unwrap! 
                (map-get? digital_asset_registry { asset_identifier: asset_identifier }) 
                ERROR_DIGITAL_ASSET_NOT_FOUND))
            
            ;; Retrieve the licensing tiers
            (license_tiers (unwrap! 
                (map-get? asset_licensing_tiers { asset_identifier: asset_identifier }) 
                ERROR_TIER_NOT_CONFIGURED))
            
            ;; Determine the price based on the selected tier
            (tier_price 
                (if (is-eq tier "basic")
                    (get basic_license_price license_tiers)
                    (if (is-eq tier "premium")
                        (get premium_license_price license_tiers)
                        (if (is-eq tier "enterprise")
                            (get enterprise_license_price license_tiers)
                            u0)  ;; Invalid tier
                    )
                )
            )
            
            ;; Calculate revenue split
            (revenue_split (calculate_revenue_distribution tier_price))
            (content_creator (get content_creator digital_asset))
            (current_block stacks-block-height)
        )
        
        ;; Validate inputs
        (asserts! (> asset_identifier u0) ERROR_INVALID_DIGITAL_ASSET_ID)
        (asserts! (not (is_license_currently_valid tx-sender asset_identifier)) ERROR_ASSET_ALREADY_OWNED)
        (asserts! (> tier_price u0) ERROR_INVALID_LICENSE_TIER)
        
        ;; Transfer funds
        (try! (transfer_stx_funds tier_price (as-contract tx-sender)))
        
        ;; Update creator earnings
        (map-set creator_earnings
            { content_creator: content_creator }
            {
                accumulated_balance: (+ 
                    (default-to u0 (get accumulated_balance 
                        (map-get? creator_earnings { content_creator: content_creator })))
                    (get creator_share revenue_split))
            }
        )
        
        ;; Record asset acquisition with tier information
        (map-set user_asset_licenses
            { license_holder: tx-sender, asset_identifier: asset_identifier }
            {
                acquisition_block_height: current_block,
                subscription_expiration_block: (if (get supports_subscription digital_asset)
                                                   (+ current_block (get subscription_period_blocks digital_asset))
                                                   u0),
                license_active: true,
                license_tier: tier
            }
        )
        
        (ok true)
    )
)

(define-public (purchase_digital_asset (asset_identifier uint))
    (let
        (
            (digital_asset (unwrap! 
                (map-get? digital_asset_registry { asset_identifier: asset_identifier }) 
                ERROR_DIGITAL_ASSET_NOT_FOUND))
            (revenue_split (calculate_revenue_distribution (get purchase_price digital_asset)))
            (content_creator (get content_creator digital_asset))
            (current_block stacks-block-height)
        )
        
        (asserts! (not (is_license_currently_valid tx-sender asset_identifier)) ERROR_ASSET_ALREADY_OWNED)
        
        (try! (transfer_stx_funds (get purchase_price digital_asset) (as-contract tx-sender)))
        
        ;; Update creator earnings
        (map-set creator_earnings
            { content_creator: content_creator }
            {
                accumulated_balance: (+ 
                    (default-to u0 (get accumulated_balance 
                        (map-get? creator_earnings { content_creator: content_creator })))
                    (get creator_share revenue_split))
            }
        )
        
        ;; Record asset acquisition
        (map-set user_asset_licenses
            { license_holder: tx-sender, asset_identifier: asset_identifier }
            {
                acquisition_block_height: current_block,
                subscription_expiration_block: (if (get supports_subscription digital_asset)
                                                   (+ current_block (get subscription_period_blocks digital_asset))
                                                   u0),
                license_active: true,
                license_tier: "standard"  ;; Default tier for non-tiered purchases
            }
        )
        
        (ok true)
    )
)

(define-public (withdraw_creator_earnings)
    (let
        (
            (earnings_record (unwrap! (map-get? creator_earnings { content_creator: tx-sender }) ERROR_DIGITAL_ASSET_NOT_FOUND))
            (withdrawable_amount (get accumulated_balance earnings_record))
        )
        
        (asserts! (> withdrawable_amount u0) ERROR_INSUFFICIENT_PAYMENT)
        
        ;; Reset balance before transfer
        (map-set creator_earnings
            { content_creator: tx-sender }
            { accumulated_balance: u0 }
        )
        
        (try! (transfer_stx_funds withdrawable_amount tx-sender))
        (ok true)
    )
)

;; Read-Only Informational Functions
(define-read-only (get_digital_asset_details (asset_identifier uint))
    (map-get? digital_asset_registry { asset_identifier: asset_identifier })
)

(define-read-only (get_user_asset_license_details 
    (user principal) 
    (asset_identifier uint))
    (map-get? user_asset_licenses 
        { license_holder: user, asset_identifier: asset_identifier })
)

;; Additional read-only function to get licensing tiers for an asset
(define-read-only (get_asset_licensing_tiers (asset_identifier uint))
    (map-get? asset_licensing_tiers { asset_identifier: asset_identifier })
)

(define-read-only (get_creator_current_balance (content_creator principal))
    (default-to u0 (get accumulated_balance (map-get? creator_earnings { content_creator: content_creator })))
)

(define-read-only (verify_asset_access (user principal) (asset_identifier uint))
    (begin
        (asserts! (> asset_identifier u0) ERROR_INVALID_DIGITAL_ASSET_ID)
        (match (map-get? user_asset_licenses { license_holder: user, asset_identifier: asset_identifier })
            current_license (ok (is_license_currently_valid user asset_identifier))
            ERROR_DIGITAL_ASSET_NOT_FOUND
        )
    )
)

;; Administrative Control Functions
(define-public (update_platform_commission_rate (new_commission_rate uint))
    (begin
        (asserts! (is-eq tx-sender (var-get platform_administrator)) ERROR_UNAUTHORIZED)
        (asserts! (<= new_commission_rate u1000) ERROR_INVALID_PRICING)
        (var-set platform_commission_rate new_commission_rate)
        (ok true)
    )
)

(define-public (transfer_platform_administrator (new_administrator principal))
    (begin
        (asserts! (is-eq tx-sender (var-get platform_administrator)) ERROR_UNAUTHORIZED)
        (asserts! (not (is-eq new_administrator 'SP000000000000000000002Q6VF78)) ERROR_INVALID_ADMIN_ADDRESS)
        (var-set platform_administrator new_administrator)
        (ok true)
    )
)