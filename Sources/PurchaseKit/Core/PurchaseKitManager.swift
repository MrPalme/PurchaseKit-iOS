//
//  PurchaseKitManager.swift
//  PurchaseKit
//
//  Created by Markus Mock on 16.02.26.
//

import Foundation
import StoreKit
import Combine
import UIKit

/// Central coordinator for StoreKit-based purchases inside PurchaseKit.
///
/// `PurchaseKitManager` is the library-level “single source of truth” for purchase state.
/// The host app provides its purchasable items via `PurchaseOption`.
///
/// Responsibilities:
/// - manages the configured purchase options (mapping `productId` → option)
/// - loads StoreKit products and caches them for UI
/// - initiates purchases and receives transaction updates via `TransactionService`
/// - derives and publishes entitlement state (`EntitlementState`)
/// - optionally integrates network monitoring via `NetworkService`
/// - exposes both:
///   - `@Published` state for SwiftUI
///   - delegate callbacks for UIKit / legacy flows
///
/// Threading model:
/// - UI-facing state (`@Published`) is mutated on the main thread.
/// - StoreKit transaction listening is handled by `TransactionService`.
/// - Network changes are received on main thread via `NetworkServiceDelegate`.
///
/// - Important: The host app must call `configure(options:)` before using the manager.
/// - Note: This type is intentionally **not** a singleton. The host app decides lifetime/scope.
@MainActor
public final class PurchaseKitManager: ObservableObject, PurchaseKitManagerProtocol {
    
    // MARK: - Published State
    
    /// Latest entitlement snapshot derived from StoreKit.
    @Published public private(set) var entitlements: [AnyPurchaseOption: EntitlementState] = [:]
    
    /// Loaded StoreKit products for configured options.
    @Published public private(set) var availableProducts: [Product] = []
    
    /// Transient UI flow state (loading spinners, pending, inline errors).
    @Published public private(set) var flowState: PurchaseFlowState = .idle
    
    /// `true` when network conditions allow product loading / purchase attempts.
    @Published public private(set) var canAttemptNetworkOperations: Bool = true
    
    /// Optional user-facing error message (library does not enforce UX).
    @Published public private(set) var errorMessage: String?
    
    // MARK: - Derived State

    /// `true` if at least one configured **auto-renewable subscription** is currently active.
    ///
    /// This is a UI convenience for paywalls/settings screens (e.g. showing “Subscribed” state).
    /// It only considers options where `purchaseType == .autoRenewableSubscription`.
    ///
    /// - Important: This does **not** include non-consumables. Use `hasAnyActiveEntitlement`
    ///   if you want a broader “premium unlocked” check.
    /// - Note: Requires `configure(options:)` to be called first.
    public var hasAnyActiveSubscription: Bool {
        activeSubscriptions.isEmpty == false
    }

    /// Returns all configured options that represent an **active subscription**.
    ///
    /// The result is derived from `entitlements` and filtered by:
    /// - `option.purchaseType == .autoRenewableSubscription`
    /// - `EntitlementState.isActive == true`
    ///
    /// The array is sorted by `sortOrder` to keep UI stable.
    ///
    /// - Note: If you enforce subscription exclusivity, this will typically contain **at most one**
    ///   element. If multiple subscriptions are active (edge case), all active ones are returned.
    public var activeSubscriptions: [AnyPurchaseOption] {
        entitlements
            .filter { (option, state) in
                option.purchaseType == .autoRenewableSubscription && state.isActive
            }
            .map(\.key)
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// A single “primary” active subscription option, if any.
    ///
    /// Use this if your product model enforces subscription exclusivity (e.g. only one tier can be active).
    /// If multiple subscriptions are active (edge case), the first by `sortOrder` is returned.
    ///
    /// - Returns: The primary active subscription option, or `nil` if none is active.
    public var primaryActiveSubscription: AnyPurchaseOption? {
        activeSubscriptions.first
    }

    /// `true` if **any** entitlement is active (subscriptions OR non-consumables).
    ///
    /// Useful for “premium unlocked” apps where either a lifetime purchase OR a subscription
    /// should unlock functionality.
    ///
    /// - Note: This is a snapshot-based convenience derived from `entitlements`.
    public var hasAnyActiveEntitlement: Bool {
        entitlements.values.contains(where: { $0.isActive })
    }
    
    // MARK: - Delegate
    
    public weak var delegate: PurchaseKitDelegate?
    
    // MARK: - Services
    
    private let productService: ProductService
    private let transactionService: TransactionService
    private let networkService: NetworkService?
    
    // MARK: - Option Storage
    
    /// Options configured by the host (type-erased for stable API).
    private var options: [AnyPurchaseOption] = []
    
    /// `productId` → option lookup for quick mapping.
    private var optionByProductId: [String: AnyPurchaseOption] = [:]
    
    // MARK: - Init
    
    /// Creates a new manager instance.
    ///
    /// - Parameters:
    ///   - productService: Service used to load StoreKit `Product`s (injectable for tests).
    ///   - transactionService: Service used to process StoreKit transactions (injectable for tests).
    ///   - networkService: Optional service to monitor connectivity.
    public init(
        productService: ProductService = ProductService(),
        transactionService: TransactionService = TransactionService(),
        networkService: NetworkService? = nil
    ) {
        self.productService = productService
        self.transactionService = transactionService
        self.networkService = networkService
        
        self.transactionService.delegate = self
        
        if let networkService {
            networkService.delegate = self
            networkService.startMonitoring()
            self.canAttemptNetworkOperations = networkService.canAttemptNetworkOperations
        }
    }
    
    deinit {
        networkService?.stopMonitoring()
        transactionService.stopListening()
    }
    
    // MARK: - Configuration
    
    /// Configures the manager with the host app's purchasable options.
    ///
    /// Call once during app start / paywall setup. This:
    /// - stores the options
    /// - enables transaction listening so background updates map to known options
    /// - prepares internal lookups (productId → option)
    ///
    /// - Parameter options: The host app-defined purchasable options.
    public func configure<Option: PurchasableOption>(options: [Option]) {
        let erased = options.map { AnyPurchaseOption($0) }
        self.options = erased
        self.optionByProductId = Dictionary(uniqueKeysWithValues: erased.map { ($0.productId, $0) })
        
        transactionService.startListening(options: options)
        
        // Initialize entitlement defaults for known options (inactive).
        // StoreKit remains source of truth; this is just a stable baseline for UI.
        var initial: [AnyPurchaseOption: EntitlementState] = [:]
        for option in erased {
            initial[option] = entitlements[option] ?? .inactive
        }
        entitlements = initial
    }
    
    // MARK: - Public Access
    
    /// Returns `true` if the given option is currently entitled (active).
    ///
    /// This is a convenience wrapper around `entitlementState(for:)`.
    /// For subscriptions this means the subscription is currently active.
    /// For non-consumables this means it was purchased and not revoked/refunded.
    ///
    /// - Parameter option: The type-erased purchase option to check.
    /// - Returns: `true` if the entitlement is active, otherwise `false`.
    public func isPurchased<Option: PurchasableOption>(_ option: Option) -> Bool {
        entitlementState(for: option).isActive
    }
    
    // MARK: - Product Loading
    
    /// Loads StoreKit products for the configured options.
    ///
    /// - Note: Also reports results via the delegate.
    public func loadProducts() async {
        guard canAttemptNetworkOperations else {
            let err: PurchaseError = .networkError
            errorMessage = err.localizedDescription
            delegate?.purchaseKitManager(self, didFailToLoadProductsWith: err)
            return
        }
        
        flowState = .purchasing
        errorMessage = nil
        
        do {
            let productsByIds = try await productService.loadProducts(for: options)
            availableProducts = Array(productsByIds.values)
            flowState = .idle
            delegate?.purchaseKitManager(self, didLoadProducts: availableProducts)
        } catch let err as PurchaseError {
            flowState = .idle
            errorMessage = err.localizedDescription
            delegate?.purchaseKitManager(self, didFailToLoadProductsWith: err)
        } catch {
            let err: PurchaseError = .networkError
            flowState = .idle
            errorMessage = err.localizedDescription
            delegate?.purchaseKitManager(self, didFailToLoadProductsWith: err)
        }
    }
    
    // MARK: - Purchase
    
    /// Initiates a purchase flow for the given typed `PurchaseOption`.
    ///
    /// This overload is a convenience for host apps that use strongly-typed option models.
    /// Internally the option is type-erased into `AnyPurchaseOption`.
    ///
    /// - Parameter option: The typed purchase option defined by the host app.
    /// - Throws: `PurchaseError` when the purchase fails or cannot be started.
    public func purchase<Option: PurchasableOption>(_ option: Option) async throws {
        let anyOption = AnyPurchaseOption(option)
        guard canAttemptNetworkOperations else {
            errorMessage = PurchaseError.networkError.localizedDescription
            flowState = .failed(.networkError)
            delegate?.purchaseKitManager(self, didUpdateFlowState: flowState)
            throw PurchaseError.networkError
        }
        
        guard let product = product(for: option) else {
            errorMessage = PurchaseError.productUnavailable.localizedDescription
            flowState = .failed(.productUnavailable)
            delegate?.purchaseKitManager(self, didUpdateFlowState: flowState)
            throw PurchaseError.productUnavailable
        }
        
        flowState = .purchasing
        delegate?.purchaseKitManager(self, didUpdateFlowState: flowState)
        errorMessage = nil
        
        do {
            _ = try await transactionService.purchase(option, product: product)
            // Result is handled via transaction callbacks.
        } catch let err as PurchaseError {
            flowState = .failed(err)
            delegate?.purchaseKitManager(self, didUpdateFlowState: flowState)
            delegate?.purchaseKitManager(self, didFailPurchaseFor: anyOption, error: err)
            throw err
        } catch {
            let err: PurchaseError = .systemError
            flowState = .failed(err)
            delegate?.purchaseKitManager(self, didUpdateFlowState: flowState)
            delegate?.purchaseKitManager(self, didFailPurchaseFor: anyOption, error: err)
            throw err
        }
    }
    
    // MARK: - Restore / Refresh
    
    /// Restores purchases using the host app's typed options.
    ///
    /// This is required because `TransactionService` builds a typed snapshot first.
    ///
    /// - Parameter options: The host app-defined purchasable options.
    public func restorePurchases<Option: PurchasableOption>(options: [Option]) async {
        flowState = .purchasing
        delegate?.purchaseKitManager(self, didUpdateFlowState: flowState)
        
        await transactionService.restorePurchases(options: options)
        
        flowState = .idle
        delegate?.purchaseKitManager(self, didUpdateFlowState: flowState)
    }
    
    /// Refreshes entitlements from the App Store for the given typed options.
    ///
    /// - Parameter options: The host app-defined purchasable options.
    public func refreshPurchases<Option: PurchasableOption>(options: [Option]) async {
        guard canAttemptNetworkOperations else {
            IAPLogger.log("Skipping refreshPurchases(options:) - no network available.", level: .warning)
            return
        }
        
        let snapshot = await transactionService.processCurrentEntitlements(options: options)
        let erased = Dictionary(uniqueKeysWithValues: snapshot.map { (AnyPurchaseOption($0.key), $0.value) })
        
        applyEntitlementSnapshot(erased, notifyDelegate: true)
    }
    
    // MARK: - Lookup
    
    /// Returns the current entitlement state for a given option.
    public func entitlementState<Option: PurchasableOption>(for option: Option) -> EntitlementState {
        let option = AnyPurchaseOption(option)
        return entitlements[option] ?? .inactive
    }
    
    /// Convenience check for feature gating.
    public func isEntitled<Option: PurchasableOption>(_ option: Option) -> Bool {
        entitlementState(for: option).isActive
    }
    
    /// Returns a loaded StoreKit product matching an option (if available).
    public func product<Option: PurchasableOption>(for option: Option)-> Product? {
        availableProducts.first(where: { $0.id == option.productId })
    }
    
    // MARK: - Promo Codes
    
    /// Presents Apple's native offer code redemption sheet (StoreKit 2).
    ///
    /// This shows the system UI where users can enter subscription offer codes.
    /// The outcome is **not** returned directly. Any resulting entitlement changes
    /// arrive later via StoreKit transaction updates (handled by `TransactionService`).
    ///
    /// - Parameter presentingViewController: A view controller currently attached to a window.
    /// - Throws: `PromoCodeError.notAvailable` if the sheet cannot be presented (e.g. no active scene),
    ///           `PromoCodeError.systemError` if StoreKit reports an error.
    ///
    /// - Important:
    ///   - Must be called on the main thread.
    ///   - The view controller must be on screen (must have a `windowScene`).
    /// - Note:
    ///   This API is available on iOS 16+. PurchaseKit already declares iOS 16 as minimum.
    public func presentPromoCodeRedemption(from presentingViewController: UIViewController) async throws {
        // We need a valid window scene for StoreKit.
        guard let scene = presentingViewController.view.window?.windowScene else {
            IAPLogger.log("Promo code redemption not available: no UIWindowScene from presenting VC", level: .warning)
            throw PromoCodeError.notAvailable
        }
        
        do {
            try await AppStore.presentOfferCodeRedeemSheet(in: scene)
            IAPLogger.log("Offer code redeem sheet presented")
            
            // Optional: reflect "busy" state briefly if you want,
            // but don't set `.purchasing` permanently because redemption is not a purchase result.
            // flowState = .idle
        } catch {
            IAPLogger.log("Offer code redeem sheet failed: \(error.localizedDescription)", level: .error)
            throw PromoCodeError.systemError
        }
    }
    
    // MARK: - Internals
    
    /// Applies a new entitlement snapshot and enforces subscription exclusivity (per offering).
    ///
    /// - Parameters:
    ///   - snapshot: The new entitlement snapshot.
    ///   - notifyDelegate: Whether to send delegate callbacks for the snapshot.
    private func applyEntitlementSnapshot(
        _ snapshot: [AnyPurchaseOption: EntitlementState],
        notifyDelegate: Bool
    ) {
        let reduced = SubscriptionExclusivityPolicy.reduce(current: entitlements, incoming: snapshot)
        entitlements = reduced
        
        if notifyDelegate {
            delegate?.purchaseKitManager(self, didCompleteRestoreWith: reduced)
        }
    }
}

// MARK: - SubscriptionManagement

public extension PurchaseKitManager {
    
    /// Opens the system subscription management UI for the current app.
    ///
    /// The method attempts to:
    /// - Resolve the currently active `UIWindowScene` in the foreground.
    /// - Present the App Store "Manage Subscriptions" sheet for that scene using
    ///   `AppStore.showManageSubscriptions(in:)`.
    @MainActor
    static func openManageSubscription() async {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
        else { return }
        
        do {
            try await AppStore.showManageSubscriptions(in: scene)
        } catch {
            IAPLogger.log("Cannot open manage subscriptions: \(error)")
        }
    }
}

// MARK: - TransactionServiceDelegate

extension PurchaseKitManager: TransactionServiceDelegate {
    
    nonisolated public func transactionService(_ service: TransactionService,
                                               didUpdateEntitlement entitlement: EntitlementState,
                                               for option: AnyPurchaseOption) {
        Task { @MainActor in
            applyEntitlementSnapshot([option: entitlement], notifyDelegate: false)
            delegate?.purchaseKitManager(self, didUpdateEntitlement: entitlement, for: option)
            flowState = .idle
            delegate?.purchaseKitManager(self, didUpdateFlowState: flowState)
        }
    }
    
    nonisolated public func transactionService(_ service: TransactionService, didFailRestore error: PurchaseError) {
        Task { @MainActor in
            flowState = .failed(error)
            delegate?.purchaseKitManager(self, didUpdateFlowState: flowState)
            delegate?.purchaseKitManager(self, didFailRestoreWith: error)
        }
    }
    
    nonisolated public func transactionService(_ service: TransactionService,
                                               didFinishRestoreWith entitlements: [AnyPurchaseOption: EntitlementState]) {
        Task { @MainActor in
            applyEntitlementSnapshot(entitlements, notifyDelegate: true)
            flowState = .idle
            delegate?.purchaseKitManager(self, didUpdateFlowState: flowState)
        }
    }
    
    nonisolated public func transactionService(_ service: TransactionService,
                                               didFailPurchaseFor option: AnyPurchaseOption,
                                               error: PurchaseError) {
        Task { @MainActor in
            flowState = .failed(error)
            delegate?.purchaseKitManager(self, didUpdateFlowState: flowState)
            delegate?.purchaseKitManager(self, didFailPurchaseFor: option, error: error)
        }
    }
    
    nonisolated public func transactionService(_ service: TransactionService, didSetPendingFor option: AnyPurchaseOption) {
        Task { @MainActor in
            flowState = .pending
            delegate?.purchaseKitManager(self, didUpdateFlowState: flowState)
        }
    }
}

// MARK: - NetworkServiceDelegate

extension PurchaseKitManager: NetworkServiceDelegate {
    
    nonisolated public func networkService(_ service: NetworkService, didUpdateNetworkStatus status: NetworkService.NetworkStatus) {
        Task { @MainActor in
            canAttemptNetworkOperations = status.allowsNetworkOperations
        }
    }
    
    nonisolated public func networkService(_ service: NetworkService, didRestoreNetworkConnectivity status: NetworkService.NetworkStatus) {
        Task { @MainActor in
            canAttemptNetworkOperations = true
        }
    }
    
    nonisolated public func networkService(_ service: NetworkService, didLoseNetworkConnectivity status: NetworkService.NetworkStatus) {
        Task { @MainActor in
            canAttemptNetworkOperations = false
        }
    }
    
    nonisolated public func networkService(_ service: NetworkService, didEncounterError error: NetworkServiceError) {
        Task { @MainActor in
            IAPLogger.log("Network service error: \(error.debugDescription)", level: .warning)
            // conservative
            canAttemptNetworkOperations = false
        }
    }
}
