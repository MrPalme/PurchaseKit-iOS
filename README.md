# PurchaseKit

PurchaseKit is an **app-agnostic StoreKit 2 backend** packaged as a Swift Package.  
It provides a reusable purchase flow (load products, purchase, restore, entitlement snapshot) plus **SwiftUI-ready building blocks** (e.g. purchase button + info/legal menu) while keeping the **host app in control** via protocols and callbacks.

Licensed under **Apache-2.0**.

---

## Features

- **StoreKit 2 product loading**
  - Loads products for your app-defined `PurchasableOption`s
  - Publishes `availableProducts` for paywalls/settings UI
- **Purchasing**
  - StoreKit 2 purchase flow
  - Verification + finishing transactions
  - Normalized `PurchaseFlowState` (`idle`, `purchasing`, `pending`, `failed`)
- **Restore / Sync**
  - `AppStore.sync()` restore flow
  - Rebuilds entitlements from `Transaction.currentEntitlements`
- **Entitlements**
  - Normalized `EntitlementState` (`inactive`, `nonConsumable`, `subscriptionActive`, `subscriptionExpired`, `revoked`)
  - Convenience checks for gating (`isActive`, `isEntitled(...)`)
- **Offerings & Features (optional)**
  - Group options via `offeringId` (paywall sections)
  - Host-defined `Feature` + `PurchaseOffering` to model “what gets unlocked”
- **Optional network awareness**
  - Inject a `NetworkService` to expose `canAttemptNetworkOperations`
- **SwiftUI building blocks**
  - `PurchaseKitPurchaseButton` (localized defaults, customizable providers)
  - `PurchaseKitInfoToolbar` (terms/privacy/info/restore/manage)
  - `PurchaseKitSafariView` for legal links

---

## Requirements

- iOS **16+**
- Swift Package Manager
- StoreKit 2

---

## Installation

Xcode → **File → Add Packages…** → paste your repository URL → add the `PurchaseKit` product.

---

## Quick Setup (Recommended)

### 1) Define your purchasable options

```swift
import PurchaseKit

enum AppPurchaseOption: String, CaseIterable, PurchasableOption {
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

    // Optional UI metadata
    var title: String { rawValue }
    var subtitle: String? { nil }

    var sortOrder: Int {
        switch self {
        case .proMonthly: return 0
        case .proYearly: return 1
        case .lifetime: return 2
        }
    }

    /// Groups options into paywall sections (optional).
    var offeringId: String? { "pro" }

    /// Optional badge shown by host UI (or your own views).
    var badge: TierBadge? { nil }
}
```

### 2) Install PurchaseKit into your SwiftUI app

This attaches one PurchaseKitManager as an EnvironmentObject, calls configure(...) once, and loads products once.

```swift
import SwiftUI
import PurchaseKit

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .installPurchaseKit(with: AppPurchaseOption.allCases)
        }
    }
}
```

### 3) Use it anywhere via @EnvironmentObject

```swift
import SwiftUI
import PurchaseKit

struct RootView: View {
    @EnvironmentObject private var purchases: PurchaseKitManager

    var body: some View {
        List {
            Text("Products: \(purchases.availableProducts.count)")
            Text("Pro active: \(purchases.hasAnyActiveSubscription.description)")
        }
    }
}
```

## Optional: Install with NetworkService

PurchaseKit does not require reachability — StoreKit is the source of truth and will error when offline.
If you want fast-fail UX + canAttemptNetworkOperations, inject a manager configured with NetworkService.

```swift
import SwiftUI
import PurchaseKit

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .installPurchaseKit(
                    with: AppPurchaseOption.allCases,
                    networkService: NetworkService()
                )
        }
    }
}
```

## Offerings (Grouping Paywall Options)

PurchasableOption.offeringId lets you group options into paywall sections.
Typical use cases:
- group **monthly + yearly** under one plan (e.g. `"pro"`)
- separate **consumer vs team** offerings
- build a paywall with multiple sections

Example:

```swift
extension Array where Element == AnyPurchaseOption {
    func groupedByOffering() -> [(offeringId: String, items: [AnyPurchaseOption])] {
        let grouped = Dictionary(grouping: self) { $0.offeringId ?? "default" }
        return grouped
            .map { (key: $0.key, value: $0.value.sorted { $0.sortOrder < $1.sortOrder }) }
            .sorted { $0.key < $1.key }
            .map { (offeringId: $0.key, items: $0.value) }
    }
}
```

Usage in SwiftUI:

```swift
import SwiftUI
import PurchaseKit

struct OfferingsList: View {
    @EnvironmentObject private var purchases: PurchaseKitManager

    var body: some View {
        let offerings = purchases.entitlements.keys.map { $0 }.groupedByOffering()

        List {
            ForEach(offerings, id: \.offeringId) { offering in
                Section(offering.offeringId) {
                    ForEach(offering.items, id: \.self) { option in
                        let state = purchases.entitlementState(for: option)
                        Text("\(option.title) – active: \(state.isActive.description)")
                    }
                }
            }
        }
    }
}
```

Tip: Use badge (e.g. “Best Value”) + sortOrder to drive paywall layout consistently.

## Optional: Feature Gating

If you want to describe what a tier unlocks, define features in the host app:

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
}```

And (optionally) map them to an offering:

```swift
import PurchaseKit

enum AppPurchaseOffering: CaseIterable, PurchaseOffering {
    case fullversion

    var id: String { "fullversion" }
    var title: String { "Full Version" }
    var description: String? { "All features available" }
    var features: [any Feature] { AppPurchaseFeature.allCases }
    var sortOrder: Int { 0 }
}}```

## UI Building Blocks

###PurchaseKitPurchaseButton

A package-ready CTA button with localized defaults and customization hooks.

```swift
import SwiftUI
import PurchaseKit

struct PaywallCTA: View {
    @EnvironmentObject private var purchases: PurchaseKitManager
    let option: AnyPurchaseOption

    var body: some View {
        PurchaseKitPurchaseButton(
            entitlement: purchases.entitlementState(for: option),
            flowState: purchases.flowState
        ) {
            Task { try? await purchases.purchase(option) }
        }
    }
}
```

###PurchaseKitInfoToolbar

A small toolbar menu for legal links and secondary actions.

```swift
import SwiftUI
import PurchaseKit

struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseKitManager

    var body: some View {
        Text("Paywall")
            .toolbar {
                PurchaseKitInfoToolbar(
                    termsURL: URL(string: "https://example.com/terms"),
                    privacyURL: URL(string: "https://example.com/privacy"),
                    infoView: AnyView(Text("Some info / disclaimer")),
                    onRestore: {
                        Task { await purchases.restorePurchases(options: AppPurchaseOption.allCases) }
                    },
                    onManageSubscriptions: {
                        Task { await PurchaseKitManager.openManageSubscription() }
                    }
                )
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
```

## Notes
•    PurchaseKit is not a singleton — you control scope/lifetime (recommended: install once at app root).
•    Restore/refresh require typed options (your PurchasableOption list) so entitlements can be mapped safely.
•    Localization in package UI uses Bundle.module.

## Support

If you find PurchaseKit useful, a ⭐️ on GitHub is appreciated.
