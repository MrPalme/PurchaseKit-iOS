//
//  PurchaseKitHost.swift
//  PurchaseKit
//
//  Created by Markus Mock on 17.02.26.
//

import SwiftUI

/// Hosts a single `PurchaseKitManager` instance and injects it into the SwiftUI environment.
///
/// Use this wrapper at the root of your SwiftUI hierarchy to provide a stable, shared
/// `PurchaseKitManager` via `EnvironmentObject`.
///
/// The host performs the initial bootstrap exactly once per view lifetime:
/// - configures the manager with your purchasable options
/// - loads StoreKit products for those options
///
/// The manager instance is owned by this view via `@StateObject` to ensure a stable lifecycle.
///
/// Threading:
/// - This view runs on the main actor, as it interacts with UI state and `ObservableObject`.
@MainActor
public struct PurchaseKitHost<Content: View, Option: PurchasableOption>: View {
    
    // MARK: - State
    
    /// The shared purchase coordinator injected into the environment.
    @StateObject private var purchases: PurchaseKitManager
    
    /// The app-defined purchasable options used to configure the manager.
    private let options: [Option]
    
    /// The root content that receives the manager via `EnvironmentObject`.
    private let content: Content
    
    /// Ensures the bootstrap (`configure` + `loadProducts`) runs only once.
    @State private var didSetup = false
    
    // MARK: - Initialization
    
    /// Creates a host that injects a `PurchaseKitManager` into the SwiftUI environment.
    ///
    /// - Parameters:
    ///   - options: The app-defined purchasable options used to configure PurchaseKit.
    ///   - manager: Factory for the manager instance. Override to inject a customized manager
    ///     (e.g. for tests or when providing a `NetworkService`).
    ///   - content: The root content that should receive the manager via `EnvironmentObject`.
    public init(
        options: [Option],
        manager: @autoclosure @escaping () -> PurchaseKitManager = PurchaseKitManager(),
        @ViewBuilder content: () -> Content
    ) {
        self.options = options
        self._purchases = StateObject(wrappedValue: manager())
        self.content = content()
    }
    
    // MARK: - View
    
    public var body: some View {
        content
            .environmentObject(purchases)
            .task {
                guard !didSetup else { return }
                didSetup = true
                purchases.configure(options: options)
                await purchases.loadProducts()
            }
    }
}

public extension View {
    
    /// Installs PurchaseKit into the view hierarchy for the given purchasable options.
    ///
    /// Call this once near the root of your app to make `PurchaseKitManager` available via
    /// `@EnvironmentObject` in all descendant views.
    ///
    /// The installation performs the required bootstrap:
    /// - `configure(options:)`
    /// - initial `loadProducts()`
    ///
    /// ## Usage
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             RootView()
    ///                 .installPurchaseKit(with: AppPurchaseOption.allCases)
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter options: The purchasable options used to configure PurchaseKit.
    /// - Returns: A wrapped view hierarchy with PurchaseKit installed.
    @MainActor
    func installPurchaseKit<Option: PurchasableOption>(
        with options: [Option]
    ) -> some View {
        PurchaseKitHost(options: options) { self }
    }
    
    /// Installs PurchaseKit and optionally enables network-aware UX by injecting a `NetworkService`.
    ///
    /// PurchaseKit does not require reachability; StoreKit is the source of truth and will surface
    /// errors when offline. Providing a `NetworkService` is purely a UX improvement so your UI can:
    /// - disable "Buy" / "Restore" buttons when offline
    /// - fail fast with a user-friendly error before calling StoreKit
    /// - observe `PurchaseKitManager.canAttemptNetworkOperations`
    ///
    /// ## Usage
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             RootView()
    ///                 .installPurchaseKit(
    ///                     with: AppPurchaseOption.allCases,
    ///                     networkService: NetworkService()
    ///                 )
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - options: The purchasable options used to configure PurchaseKit.
    ///   - networkService: Optional connectivity monitor used for UX gating. Pass `nil` to disable.
    /// - Returns: A wrapped view hierarchy with PurchaseKit installed.
    @MainActor
    func installPurchaseKit<Option: PurchasableOption>(
        with options: [Option],
        networkService: NetworkService? = nil
    ) -> some View {
        PurchaseKitHost(
            options: options,
            manager: PurchaseKitManager(networkService: networkService)
        ) { self }
    }
    
    /// Installs PurchaseKit using a custom manager instance.
    ///
    /// Use this overload when you want full control over the manager configuration, e.g.:
    /// - injecting mocked services for previews/tests
    /// - providing a custom `ProductService` / `TransactionService`
    /// - providing a `NetworkService`
    ///
    /// The manager is created lazily via a factory to avoid eager initialization.
    ///
    /// ## Usage
    /// ```swift
    /// let manager = PurchaseKitManager(
    ///     productService: .init(),
    ///     transactionService: .init(),
    ///     networkService: NetworkService()
    /// )
    ///
    /// RootView()
    ///     .installPurchaseKit(with: AppPurchaseOption.allCases, manager: manager)
    /// ```
    ///
    /// - Parameters:
    ///   - options: The purchasable options used to configure PurchaseKit.
    ///   - manager: Factory that creates the `PurchaseKitManager` instance to install.
    /// - Returns: A wrapped view hierarchy with PurchaseKit installed.
    @MainActor
    func installPurchaseKit<Option: PurchasableOption>(
        with options: [Option],
        manager: @autoclosure @escaping () -> PurchaseKitManager
    ) -> some View {
        PurchaseKitHost(options: options, manager: manager()) { self }
    }
}
