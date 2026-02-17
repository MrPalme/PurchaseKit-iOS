//
//  PurchaseKitPurchaseButton.swift
//  PurchaseKit
//
//  Created by Markus Mock on 17.02.26.
//

import SwiftUI

/// A prominent purchase call-to-action button that adapts its label, icon, and tint color
/// based on the current purchase state and flow.
///
/// This view is designed to be **package-ready**:
/// - Uses system defaults for spacing/sizing (no host app design tokens required)
/// - Uses `Bundle.module` for localization (works in Swift Package Manager)
/// - Exposes customization points (title/icon/tint) via closures
///
/// Typical usage:
/// ```swift
/// PurchaseKitPurchaseButton(
///   entitlement: manager.entitlementState(for: option),
///   flowState: manager.flowState,
///   action: { Task { try await manager.purchase(option) } }
/// )
/// ```
///
/// If you want custom copy/icons/colors, pass the provider closures.
@MainActor
public struct PurchaseKitPurchaseButton: View {

    // MARK: - Types

    /// Produces a button title for the given entitlement and flow state.
    public typealias TitleProvider = @MainActor (_ entitlement: EntitlementState, _ flowState: PurchaseFlowState) -> String

    /// Produces an icon for the given entitlement and flow state.
    public typealias IconProvider = @MainActor (_ entitlement: EntitlementState, _ flowState: PurchaseFlowState) -> Image

    /// Produces a tint color for the given entitlement and flow state.
    public typealias TintProvider = @MainActor (_ entitlement: EntitlementState, _ flowState: PurchaseFlowState) -> Color

    // MARK: - Input

    private let entitlement: EntitlementState
    private let flowState: PurchaseFlowState
    private let titleProvider: TitleProvider
    private let iconProvider: IconProvider
    private let tintProvider: TintProvider
    private let action: () -> Void

    // MARK: - Init

    /// Creates a PurchaseKit purchase button.
    ///
    /// - Parameters:
    ///   - entitlement: Current entitlement state for the selected option (e.g. inactive/active/expired).
    ///   - flowState: Current purchase flow state (e.g. idle/purchasing/pending/failed).
    ///   - title: Optional title provider. Defaults to PurchaseKit’s built-in localization keys.
    ///   - icon: Optional icon provider. Defaults to PurchaseKit’s SF Symbol mapping.
    ///   - tint: Optional tint provider. Defaults to PurchaseKit’s color mapping.
    ///   - action: Action called when the user taps the button.
    public init(
        entitlement: EntitlementState,
        flowState: PurchaseFlowState,
        title: @escaping TitleProvider = PurchaseKitPurchaseButtonDefaults.title,
        icon: @escaping IconProvider = PurchaseKitPurchaseButtonDefaults.icon,
        tint: @escaping TintProvider = PurchaseKitPurchaseButtonDefaults.tint,
        action: @escaping () -> Void
    ) {
        self.entitlement = entitlement
        self.flowState = flowState
        self.titleProvider = title
        self.iconProvider = icon
        self.tintProvider = tint
        self.action = action
    }

    // MARK: - View

    public var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity, minHeight: 24)
                .foregroundStyle(.white)
        }
        .buttonStyle(.borderedProminent)
        .tint(tintProvider(entitlement, flowState))
        .disabled(isBusy) // optional: prevent double-taps while purchasing
    }

    // MARK: - Internals

    private var isBusy: Bool {
        switch flowState {
        case .purchasing, .pending: return true
        default: return false
        }
    }

    @ViewBuilder
    private var label: some View {
        if isBusy {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.9)
                    .progressViewStyle(.circular)
                    .tint(.white)

                Text(PurchaseKitPurchaseButtonDefaults.processingTitle(flowState))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        } else {
            HStack(spacing: 16) {
                iconProvider(entitlement, flowState)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)

                Text(titleProvider(entitlement, flowState))
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        PurchaseKitPurchaseButton(entitlement: .inactive, flowState: .idle, action: { })
        PurchaseKitPurchaseButton(entitlement: .nonConsumable(transactionID: 123), flowState: .idle, action: { })
        PurchaseKitPurchaseButton(entitlement: .revoked(revocationDate: Date()), flowState: .idle, action: { })
        PurchaseKitPurchaseButton(entitlement: .subscriptionActive(expirationDate: Date(), transactionID: 123), flowState: .idle, action: { })
        PurchaseKitPurchaseButton(entitlement: .subscriptionExpired(expirationDate: Date()), flowState: .idle, action: { })
        PurchaseKitPurchaseButton(entitlement: .inactive, flowState: .failed(.productUnavailable), action: { })
        PurchaseKitPurchaseButton(entitlement: .inactive, flowState: .pending, action: { })
        PurchaseKitPurchaseButton(entitlement: .inactive, flowState: .purchasing, action: { })
    }
    .padding()
}
