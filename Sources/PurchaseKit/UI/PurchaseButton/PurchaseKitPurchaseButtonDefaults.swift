//
//  PurchaseKitPurchaseButtonDefaults.swift
//  PurchaseKit
//
//  Created by Markus Mock on 17.02.26.
//

import SwiftUI

/// Default mapping for `PurchaseKitPurchaseButton`.
///
/// You can override any of these behaviors by passing custom provider closures
/// to `PurchaseKitPurchaseButton(...)`.
@MainActor
public enum PurchaseKitPurchaseButtonDefaults {

    // MARK: - Localization Keys

    /// Namespace for default localization keys used by the button.
    public enum Key {
        public static let subscribe: String.LocalizationValue = "purchasekit.button.subscribe"
        public static let purchased: String.LocalizationValue = "purchasekit.button.purchased"
        public static let active: String.LocalizationValue = "purchasekit.button.active"
        public static let renew: String.LocalizationValue = "purchasekit.button.renew"
        public static let revoked: String.LocalizationValue = "purchasekit.button.revoked"
        public static let processing: String.LocalizationValue = "purchasekit.button.processing"
        public static let pending: String.LocalizationValue = "purchasekit.button.pending"
    }

    // MARK: - Title

    /// Default title mapping by entitlement state.
    public static func title(_ entitlement: EntitlementState, _ flowState: PurchaseFlowState) -> String {
        // If you want flowState-specific titles (e.g. "Try again"),
        // you can extend this mapping later.
        switch entitlement {
        case .inactive: return String(localized: Key.subscribe, bundle: .module)
        case .nonConsumable: return String(localized: Key.purchased, bundle: .module)
        case .subscriptionActive: return String(localized: Key.active, bundle: .module)
        case .subscriptionExpired: return String(localized: Key.renew, bundle: .module)
        case .revoked: return String(localized: Key.revoked, bundle: .module)
        }
    }

    /// Default processing title while busy (purchasing/pending).
    public static func processingTitle(_ flowState: PurchaseFlowState) -> String {
        switch flowState {
        case .pending: return String(localized: Key.pending, bundle: .module)
        default: return String(localized: Key.processing, bundle: .module)
        }
    }

    // MARK: - Icon

    /// Default SF Symbol mapping for the button icon.
    public static func icon(_ entitlement: EntitlementState, _ flowState: PurchaseFlowState) -> Image {
        switch entitlement {
        case .inactive: return Image(systemName: "crown.fill")
        case .nonConsumable: return Image(systemName: "checkmark.seal.fill")
        case .subscriptionActive: return Image(systemName: "checkmark.circle.fill")
        case .subscriptionExpired: return Image(systemName: "arrow.clockwise.circle.fill")
        case .revoked: return Image(systemName: "xmark.octagon.fill")
        }
    }

    // MARK: - Tint

    /// Default tint color mapping.
    ///
    /// Uses `.accentColor` for the inactive state so the host app theme naturally applies.
    public static func tint(_ entitlement: EntitlementState, _ flowState: PurchaseFlowState) -> Color {
        // Busy: neutral tint (avoid changing meaning while loading)
        switch flowState {
        case .purchasing, .pending: return .gray
        default: break
        }

        switch entitlement {
        case .inactive: return .accentColor
        case .nonConsumable, .subscriptionActive: return .green
        case .subscriptionExpired: return .orange
        case .revoked: return .red.opacity(0.85)
        }
    }
}
