# PurchaseKit

PurchaseKit is an **app-agnostic StoreKit 2 backend** packaged as a Swift Package.  
It provides a reusable purchase flow (load products, purchase, restore, entitlement snapshot) and a small set of **SwiftUI-ready building blocks** (e.g. restore + legal buttons) driven by **protocols + callbacks** so the host app stays in control of UI and copy.

Licensed under **Apache-2.0**.

---

## Features

- **StoreKit 2 product loading + caching**
  - Load products for your `PurchaseOption`s
  - Cache policy (`useCache` / `reloadIgnoringCache`)
- **Purchasing**
  - Initiate purchases with StoreKit 2
  - Handles verification + finishing transactions
  - Pending / cancelled / failed mapping
- **Restore / Sync**
  - `AppStore.sync()` restore flow
  - Rebuilds entitlement snapshot from `Transaction.currentEntitlements`
- **Entitlements**
  - Normalized `EntitlementState` (`inactive`, `nonConsumable`, `subscriptionActive`, `subscriptionExpired`, `revoked`)
  - `isActive` for feature gating
- **Option model**
  - Host app defines purchasables via `PurchaseOption`
  - Library uses type erasure (`AnyPurchaseOption`) for stable callbacks
- **Optional network awareness**
  - Integrate a `NetworkService` if you want to block network-dependent actions
- **SwiftUI-friendly**
  - `ObservableObject` state (`@Published`) for paywalls / settings screens
  - Delegate callbacks for UIKit or legacy flows

---

## Requirements

- iOS **16+**
- Swift Package Manager
- StoreKit 2

---

## Installation (Swift Package Manager)

Add PurchaseKit via SPM:

- Xcode → **File → Add Packages…**
- Select your repository URL
- Add the `PurchaseKit` product to your target

---

## Core Concepts

### PurchaseOption
Your app defines purchasable items by conforming to:

- `id`: stable app identifier (analytics/routing)
- `productId`: StoreKit product id (App Store Connect)
- `purchaseType`: category (subscription vs non-consumable)
- `title`, `subtitle`, `badge`, `offeringId`, `sortOrder`: UI metadata

### EntitlementState
PurchaseKit normalizes StoreKit transactions into `EntitlementState` so your app can gate features consistently.

### PurchaseKitManager
The main coordinator:
- configure options
- load products
- purchase options
- restore purchases (typed options)
- publish entitlement state

---

## Quick Start

### 1) Define your options

```swift
import PurchaseKit

enum AppPurchaseOption: String, CaseIterable, PurchaseOption {
    case proMonthly
    case proYearly
    case lifetime

    var id: String { rawValue }

    var productId: String {
        switch self {
        case .proMonthly: return "com.yourapp.pro.monthly"
        case .proYearly: return "com.yourapp.pro.yearly"
        case .lifetime: return "com.yourapp.lifetime"
        }
    }

    var purchaseType: PurchaseType {
        switch self {
        case .lifetime: return .nonConsumable
        default: return .autoRenewableSubscription
        }
    }

    var title: String { rawValue }
    
    var subtitle: String? { nil }
    
    var sortOrder: Int {
        switch self {
        case .proMonthly: return 0
        case .proYearly: return 1
        case .lifetime: return 2
    }
    
    var offeringId: String? { "pro" }
    
    var badge: TierBadge? { nil }
}
```

### 2) Create and configure the manager

```swift
import PurchaseKit

@MainActor
final class PaywallViewModel: ObservableObject {
    let manager = PurchaseKitManager()

    init() {
        manager.configure(options: AppPurchaseOption.allCases)
    }
}
```

### 3) Load products

```swift
Task {
    await manager.loadProducts()
}
```

### 4) Purchase

```swift
Task {
    try await manager.purchase(AppPurchaseOption.proYearly)
}
```

### 5) Restore

Restore requires typed options (because StoreKit entitlements are mapped via your PurchaseOption set).

```swift
Task {
    await manager.restorePurchases(options: AppPurchaseOption.allCases)
}
```

### 6) Gate features

```swift
let option = AnyPurchaseOption(AppPurchaseOption.proYearly)
let isPro = manager.isEntitled(option)
```

## Offerings (Grouping Paywall Options)

`PurchaseOption.offeringId` lets you group multiple options into a single offering/plan.
Typical use cases:
- group **monthly + yearly** under one plan (e.g. `"pro"`)
- separate **consumer vs team** offerings
- build a paywall with multiple sections

Example:

```swift
extension Array where Element == AnyPurchaseOption {
    func groupedByOffering() -> [(offeringId: String, items: [AnyPurchaseOption])] {
        let grouped = Dictionary(grouping: self) { $0.offeringId ?? "default" }
        // stable order: sort groups by offeringId, items by sortOrder
        return grouped
            .map { (key: $0.key, value: $0.value.sorted { $0.sortOrder < $1.sortOrder }) }
            .sorted { $0.key < $1.key }
            .map { (offeringId: $0.key, items: $0.value) }
    }
}
```

Usage in SwiftUI:

```swift
let offerings = manager.entitlements.keys
    .map { $0 } // AnyPurchaseOption
    .groupedByOffering()

ForEach(offerings, id: \.offeringId) { offering in
    Section(offering.offeringId) {
        ForEach(offering.items, id: \.self) { option in
            let state = manager.entitlementState(for: option)
            Text("\(option.title) – active: \(state.isActive.description)")
        }
    }
}
```

Tip: Use badge (e.g. “Best Value”) + sortOrder to drive paywall layout consistently.

## Offerings (Grouping Paywall Options)

PurchaseKit can be used to gate app functionality behind purchases by defining features in the host app and checking them against the current entitlements.

### 1) Define your features

```swift
import PurchaseKit

enum AppPurchaseFeature: CaseIterable, Feature {

    case cloudSync
    case photoCredits

    var id: String { "\(self)" }

    var localizedName: String {
        switch self {
        case .cloudSync: return "subscription_feature_cloud_sync".localized
        case .photoCredits: return "subscription_feature_shooting_credits".localized
        }
    }

    var localizeDescription: String {
        switch self {
        case .cloudSync: return "subscription_feature_cloud_sync_description".localized
        case .photoCredits: return "subscription_feature_shooting_credits_description".localized
        }
    }
}
```

### 2) Map features to purchase offering

```swift
import PurchaseKit

enum AppPurchaseOffering: CaseIterable, PurchaseOffering {
    
    case fullversion
    
    var id: String {
        switch self {
        case .fullversion: return "fullversion"
        }
    }
    
    var title: String {
        switch self {
        case .fullversion: return "Full Version"
        }
    }
    
    var description: String? {
        switch self {
        case .fullversion: return "All features available" 
        }
    }
    
    var features: [any Feature] { AppPurchaseFeature.allCases }
    
    var sortOrder: Int {
        switch self {
        case .fullversion: return 1
        }
    }
}
```

## Best Value / Savings Badges

PurchaseKit keeps UI decisions in the host app. A common pattern is:
- mark one option as **Best Value** (e.g. yearly)
- optionally show **“Save X%”** compared to a baseline (e.g. monthly)

### 1) Define badges on your options

```swift
import PurchaseKit

enum AppPurchaseOption: String, CaseIterable, PurchaseOption {
    case proMonthly
    case proYearly
    case lifetime

    var id: String { rawValue }

    var productId: String {
        switch self {
        case .proMonthly: return "com.yourapp.pro.monthly"
        case .proYearly:  return "com.yourapp.pro.yearly"
        case .lifetime:   return "com.yourapp.lifetime"
        }
    }

    var purchaseType: PurchaseType {
        switch self {
        case .lifetime: return .nonConsumable
        default: return .autoRenewableSubscription
        }
    }

    var title: String {
        switch self {
        case .proMonthly: return "Pro Monthly"
        case .proYearly:  return "Pro Yearly"
        case .lifetime:   return "Lifetime"
        }
    }

    var subtitle: String? { nil }
    
    var sortOrder: Int {
        switch self {
        case .proMonthly: return 0
        case .proYearly: return 1
        case .lifetime: return 2
    }
    
    var offeringId: String? { "pro" }

    // Example: yearly is "Best Value"
    var badge: TierBadge? {
        switch self {
        case .proYearly: return .bestValue
        default: return nil
        }
    }
}
```

### 2) Compute and display “Save X%”

Use StoreKit product pricing to compute savings per month (yearly vs monthly).
If the percentage exists, you can render it as a TierBadge.savePercent.

```swift
import StoreKit
import PurchaseKit

func savingsBadge(monthly: Product, yearly: Product) -> TierBadge? {
    guard let pct = yearly.savingsPercentage(comparedTo: monthly), pct > 0 else { return nil }
    return .savePercent(pct)
}
```

### 3) Use in a SwiftUI paywall row

```swift
import SwiftUI
import PurchaseKit
import StoreKit

struct PaywallRow: View {
    let option: AnyPurchaseOption
    let product: Product?
    let monthlyBaseline: Product? // e.g. monthly subscription product

    var computedBadge: TierBadge? {
        guard let product, let monthlyBaseline else { return option.badge }
        // Prefer computed savings badge, fallback to the option-defined badge
        return savingsBadge(monthly: monthlyBaseline, yearly: product) ?? option.badge
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(option.title)
                if let product {
                    Text(product.displayPrice).font(.subheadline).opacity(0.8)
                }
            }

            Spacer()

            if let badge = computedBadge {
                Text(badge.defaultText)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
            }
        }
    }
}
```
Note: TierBadge.defaultText is a fallback. For full localization you can map badges
to Localizable keys in the host app and render your own text instead.



### Delegate (optional)

If you prefer callbacks (UIKit / legacy), implement PurchaseKitDelegate:

```swift
final class SomeClass: PurchaseKitDelegate {
    func purchaseKitManager(_ manager: PurchaseKitManager, didUpdateEntitlement entitlement: EntitlementState, for option: AnyPurchaseOption) {
        // update UI / unlock features
    }
}
```

Assign it:

```swift
manager.delegate = coordinator
```

### Offer Code Redemption (Promo Codes)

PurchaseKit can present Apple’s native offer code redemption sheet:

```swift
try await manager.presentPromoCodeRedemption(from: viewController)
```

Notes:
    •    Applies to subscription offer codes
    •    Results are delivered via transaction updates (entitlements refresh automatically)

## Network / Reachability (Optional)

PurchaseKit does **not** require reachability. StoreKit 2 is the source of truth and will
return errors when the device is offline or the App Store is unavailable.

For better UX you can optionally inject a `NetworkService` into `PurchaseKitManager`.
If provided, the manager updates `canAttemptNetworkOperations` and can fail fast with
a user-friendly error before calling StoreKit.

```swift
let manager = PurchaseKitManager(networkService: NetworkService())
manager.configure(options: AppPurchaseOption.allCases)

// Example: block actions in UI
if manager.canAttemptNetworkOperations {
    await manager.loadProducts()
}
