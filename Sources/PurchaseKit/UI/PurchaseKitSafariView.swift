//
//  PurchaseKitSafariView.swift
//  PurchaseKit
//
//  Created by Markus Mock on 17.02.26.
//

import SwiftUI
import SafariServices

/// A SwiftUI wrapper around `SFSafariViewController` for presenting web content inside the app.
///
/// This view is intended for common purchase-related links such as:
/// - Terms of Service
/// - Privacy Policy
/// - Help / FAQ pages
///
/// Benefits over opening Safari:
/// - Keeps the user in-app
/// - Uses Apple’s secure, sandboxed Safari view controller
/// - Shares cookies and website data with Safari (expected system behavior)
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showTerms) {
///     PurchaseKitSafariView(url: URL(string: "https://example.com/terms")!)
/// }
/// ```
public struct PurchaseKitSafariView: UIViewControllerRepresentable {

    // MARK: - Properties

    /// The URL to be presented in the Safari view controller.
    private let url: URL

    // MARK: - Initialization

    /// Creates a Safari sheet for the given URL.
    ///
    /// - Parameter url: The web page to present.
    public init(url: URL) {
        self.url = url
    }

    // MARK: - UIViewControllerRepresentable

    /// Creates the underlying `SFSafariViewController`.
    ///
    /// - Parameter context: The SwiftUI context.
    /// - Returns: A configured Safari view controller.
    public func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    /// Updates the Safari view controller when SwiftUI state changes.
    ///
    /// `SFSafariViewController` does not support changing the URL after creation in a way that
    /// fits SwiftUI updates, so this is intentionally a no-op.
    ///
    /// - Parameters:
    ///   - uiViewController: The existing Safari view controller.
    ///   - context: The SwiftUI context.
    public func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) { }
}
