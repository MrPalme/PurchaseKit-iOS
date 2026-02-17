//
//  PurchaseKitInfoToolbar.swift
//  PurchaseKit
//
//  Created by Markus Mock on 17.02.26.
//

import SwiftUI

/// A toolbar menu that groups common paywall / purchase-related secondary actions.
///
/// `PurchaseKitInfoToolbar` is intended to keep paywall UI focused while still providing
/// transparent access to legal documents and recovery actions.
///
/// Supported actions:
/// - Open Terms of Service (URL)
/// - Open Privacy Policy (URL)
/// - Present an optional "Info" sheet (custom view)
/// - Restore purchases (callback)
/// - Manage subscriptions (callback)
///
/// Presentation:
/// - Legal URLs are shown inside an in-app Safari sheet (`PurchaseKitSafariView`).
/// - The optional info content is shown in a sheet (host-provided view).
///
/// Localization:
/// - Uses `Bundle.module` so default strings work when PurchaseKit is consumed via SPM.
///
/// Threading:
/// - Runs on the main actor, as it drives SwiftUI presentation state.
///
/// ## Usage
///
/// ### Basic (legal URLs + restore)
/// ```swift
/// .toolbar {
///     PurchaseKitInfoToolbar(
///         termsURL: URL(string: "https://example.com/terms"),
///         privacyURL: URL(string: "https://example.com/privacy"),
///         onRestore: { Task { await manager.restorePurchases(options: AppPurchaseOption.allCases) } }
///     )
/// }
/// ```
///
/// ### With info sheet + manage subscriptions
/// ```swift
/// .toolbar {
///     PurchaseKitInfoToolbar(
///         termsURL: URL(string: "https://example.com/terms"),
///         privacyURL: URL(string: "https://example.com/privacy"),
///         infoView: AnyView(Text("Your disclaimer / info text")),
///         onRestore: { Task { await manager.restorePurchases(options: AppPurchaseOption.allCases) } },
///         onManageSubscriptions: { Task { await PurchaseKitManager.openManageSubscription() } }
///     )
/// }
/// ```
///
/// ### With configuration (hide some entries)
/// ```swift
/// .toolbar {
///     PurchaseKitInfoToolbar(
///         configuration: .init(showsTerms: false, showsPrivacy: true, showsRestore: true, showsManageSubscriptions: false),
///         privacyURL: URL(string: "https://example.com/privacy"),
///         onRestore: { /* ... */ }
///     )
/// }
/// ```
@MainActor
public struct PurchaseKitInfoToolbar: ToolbarContent {
    
    // MARK: - Types
    
    /// Internal routing for the toolbar menu sheet presentation.
    private enum SheetRoute: Identifiable {
        /// Presents the host-provided info view.
        case info
        /// Presents a web view for a given URL.
        case web(URL)
        
        /// Stable identifier for SwiftUI sheet diffing.
        var id: String {
            switch self {
            case .info: return "info"
            case .web(let url): return "web.\(url.absoluteString)"
            }
        }
    }
    
    // MARK: - Configuration
    
    /// Controls which menu entries are visible.
    ///
    /// Visibility rules:
    /// - `showsTerms` only has an effect when `termsURL != nil`
    /// - `showsPrivacy` only has an effect when `privacyURL != nil`
    /// - `showsRestore` only has an effect when `onRestore != nil`
    /// - `showsManageSubscriptions` only has an effect when `onManageSubscriptions != nil`
    public struct Configuration: Sendable {
        
        /// Whether the Terms of Service entry is shown (requires `termsURL`).
        public var showsTerms: Bool
        /// Whether the Privacy Policy entry is shown (requires `privacyURL`).
        public var showsPrivacy: Bool
        /// Whether the Restore entry is shown (requires `onRestore`).
        public var showsRestore: Bool
        /// Whether the Manage Subscriptions entry is shown (requires `onManageSubscriptions`).
        public var showsManageSubscriptions: Bool
        
        /// Creates a configuration controlling which menu entries are visible.
        public init(
            showsTerms: Bool = true,
            showsPrivacy: Bool = true,
            showsRestore: Bool = true,
            showsManageSubscriptions: Bool = true
        ) {
            self.showsTerms = showsTerms
            self.showsPrivacy = showsPrivacy
            self.showsRestore = showsRestore
            self.showsManageSubscriptions = showsManageSubscriptions
        }
    }
    
    // MARK: - Inputs
    
    /// Visibility configuration for the menu entries.
    private let config: Configuration
    
    /// URL for Terms of Service. If `nil`, the entry is hidden.
    private let termsURL: URL?
    
    /// URL for Privacy Policy. If `nil`, the entry is hidden.
    private let privacyURL: URL?
    
    /// Callback for restoring purchases. If `nil`, the entry is hidden.
    private let onRestore: (() -> Void)?
    
    /// Callback for opening the system subscription management UI. If `nil`, the entry is hidden.
    private let onManageSubscriptions: (() -> Void)?
    
    /// Optional info sheet content, provided by the host app.
    private let infoView: AnyView?
    
    // MARK: - State
    
    /// Current sheet route presented by the toolbar menu.
    @State private var route: SheetRoute?
    
    /// Namespace for optional zoom transitions.
    @Namespace private var transitionNS
    
    // MARK: - Init
    
    /// Creates a toolbar menu that groups secondary purchase actions (legal/info/restore/manage).
    ///
    /// - Parameters:
    ///   - configuration: Controls which entries are shown.
    ///   - termsURL: URL for Terms of Service. If `nil`, the entry is hidden.
    ///   - privacyURL: URL for Privacy Policy. If `nil`, the entry is hidden.
    ///   - infoView: Optional view shown in a sheet when the user selects “Info”.
    ///   - onRestore: Callback for “Restore purchases”. If `nil`, the entry is hidden.
    ///   - onManageSubscriptions: Callback for “Manage subscriptions”. If `nil`, the entry is hidden.
    public init(
        configuration: Configuration = .init(),
        termsURL: URL? = nil,
        privacyURL: URL? = nil,
        infoView: AnyView? = nil,
        onRestore: (() -> Void)? = nil,
        onManageSubscriptions: (() -> Void)? = nil
    ) {
        self.config = configuration
        self.termsURL = termsURL
        self.privacyURL = privacyURL
        self.infoView = infoView
        self.onRestore = onRestore
        self.onManageSubscriptions = onManageSubscriptions
    }
    
    // MARK: - ToolbarContent
    
    /// Builds the toolbar menu and wires up sheet presentation.
    public var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu(
                String(localized: PurchaseKitInfoToolbarDefaults.Key.menuTitle, bundle: .module),
                systemImage: PurchaseKitInfoToolbarDefaults.Icon.menu
            ) {
                legalSection
                infoSection
                actionSection
            }
            .sheet(item: $route) { route in
                sheet(for: route)
                    .presentationDetents([.medium, .large])
                    .optionalZoomNavigationTransition(
                        sourceID: PurchaseKitInfoToolbarDefaults.Transition.sourceId,
                        in: transitionNS
                    )
            }
        }
        .optionalMatchedTransitionSource(
            id: PurchaseKitInfoToolbarDefaults.Transition.sourceId,
            in: transitionNS
        )
    }
    
    // MARK: - Sections
    
    /// Legal links section (Terms + Privacy), shown when URLs are provided.
    @ViewBuilder private var legalSection: some View {
        if config.showsTerms, let termsURL {
            Button(
                String(localized: PurchaseKitInfoToolbarDefaults.Key.terms, bundle: .module),
                systemImage: PurchaseKitInfoToolbarDefaults.Icon.terms
            ) {
                route = .web(termsURL)
            }
        }
        
        if config.showsPrivacy, let privacyURL {
            Button(
                String(localized: PurchaseKitInfoToolbarDefaults.Key.privacy, bundle: .module),
                systemImage: PurchaseKitInfoToolbarDefaults.Icon.privacy
            ) {
                route = .web(privacyURL)
            }
        }
    }
    
    /// Optional info section, shown when `infoView` is provided.
    @ViewBuilder private var infoSection: some View {
        if infoView != nil {
            if (config.showsTerms && termsURL != nil) || (config.showsPrivacy && privacyURL != nil) {
                Divider()
            }
            
            Button(
                String(localized: PurchaseKitInfoToolbarDefaults.Key.info, bundle: .module),
                systemImage: PurchaseKitInfoToolbarDefaults.Icon.info
            ) {
                route = .info
            }
        }
    }
    
    /// Action section (Restore + Manage Subscription), shown when callbacks are provided.
    @ViewBuilder private var actionSection: some View {
        if onRestore != nil || onManageSubscriptions != nil {
            Divider()
        }
        
        if config.showsRestore, let onRestore {
            Button(
                String(localized: PurchaseKitInfoToolbarDefaults.Key.restore, bundle: .module),
                systemImage: PurchaseKitInfoToolbarDefaults.Icon.restore
            ) {
                onRestore()
            }
        }
        
        if config.showsManageSubscriptions, let onManageSubscriptions {
            Button(
                String(localized: PurchaseKitInfoToolbarDefaults.Key.manage, bundle: .module),
                systemImage: PurchaseKitInfoToolbarDefaults.Icon.manage
            ) {
                onManageSubscriptions()
            }
        }
    }
    
    // MARK: - Sheet
    
    /// Builds sheet content for the given route.
    ///
    /// - Parameter route: The route selected from the menu.
    /// - Returns: A view representing the sheet content.
    @ViewBuilder private func sheet(for route: SheetRoute) -> some View {
        switch route {
        case .info: infoView ?? AnyView(EmptyView())
        case .web(let url): PurchaseKitSafariView(url: url)
        }
    }
}

// MARK: - Preview

#Preview("PurchaseKitInfoToolbar") {
    NavigationStack {
        List {
            Text("Paywall content placeholder")
            Text("Scroll / content")
        }
        .navigationTitle("Paywall")
        .toolbar {
            PurchaseKitInfoToolbar(
                termsURL: URL(string: "https://example.com/terms"),
                privacyURL: URL(string: "https://example.com/privacy"),
                infoView: AnyView(
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Information")
                            .font(.headline)
                        Text("This is a sample info sheet content provided by the host app.")
                            .font(.body)
                        Text("You can put disclaimers, support notes, or store details here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                        .padding()
                ),
                onRestore: { },
                onManageSubscriptions: { }
            )
        }
    }
}
