//
//  PurchaseKitInfoToolbarDefaults.swift
//  PurchaseKit
//
//  Created by Markus Mock on 17.02.26.
//

import SwiftUI

/// Default configuration values used by `PurchaseKitInfoToolbar`.
///
/// This namespace centralizes the **localization keys**, **SF Symbols**, and optional
/// **transition identifiers** so the toolbar implementation stays small and consistent.
///
/// Customization strategy:
/// - If you want different copy, provide your own localized strings for these keys in the
///   consuming app or fork/override the defaults.
/// - If you want different icons, change the symbol names here (or expose config later).
public enum PurchaseKitInfoToolbarDefaults {

    // MARK: - Localization Keys

    /// Default localization keys used by the toolbar.
    ///
    /// These keys are resolved with `Bundle.module` inside PurchaseKit so they work
    /// out of the box when consumed as a Swift Package.
    public enum Key {

        /// Title shown for the toolbar menu button (e.g. "Info").
        public static let menuTitle: String.LocalizationValue = "purchasekit.toolbar.menu"

        /// Menu entry title for opening the Terms of Service URL.
        public static let terms: String.LocalizationValue = "purchasekit.toolbar.terms"

        /// Menu entry title for opening the Privacy Policy URL.
        public static let privacy: String.LocalizationValue = "purchasekit.toolbar.privacy"

        /// Menu entry title for presenting the optional info/disclaimer sheet.
        public static let info: String.LocalizationValue = "purchasekit.toolbar.info"

        /// Menu entry title for triggering a restore flow.
        public static let restore: String.LocalizationValue = "purchasekit.toolbar.restore"

        /// Menu entry title for opening Apple’s “Manage Subscriptions” UI.
        public static let manage: String.LocalizationValue = "purchasekit.toolbar.manage_subscriptions"
    }

    // MARK: - SF Symbols

    /// Default SF Symbol names used by the toolbar.
    ///
    /// These are passed to SwiftUI APIs that accept `systemImage:` (SF Symbol names).
    public enum Icon {

        /// Symbol for the toolbar menu button.
        public static let menu = "info"

        /// Symbol for the Terms of Service entry.
        public static let terms = "doc.text"

        /// Symbol for the Privacy Policy entry.
        public static let privacy = "hand.raised"

        /// Symbol for the Info entry.
        public static let info = "info.circle"

        /// Symbol for the Restore entry.
        public static let restore = "arrow.clockwise"

        /// Symbol for the Manage Subscriptions entry.
        public static let manage = "creditcard"
    }

    // MARK: - Transitions

    /// Identifiers used for optional SwiftUI matched transitions / zoom transitions.
    ///
    /// PurchaseKit uses a fixed identifier so source and destination can match.
    /// On OS versions where the APIs are unavailable, the toolbar falls back to the
    /// default system sheet transition.
    public enum Transition {

        /// Matched transition identifier for the toolbar menu item / sheet.
        public static let sourceId = "purchasekit.toolbar.info"
    }
}
