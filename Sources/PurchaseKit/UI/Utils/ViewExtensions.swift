//
//  ViewExtensions.swift
//  PurchaseKit
//
//  Created by Markus Mock on 17.02.26.
//

import SwiftUI

// MARK: - iOS 18 Navigation Transition Compatibility

public extension View {
    
    /// Conditionally applies a matched transition source and does nothing on older OS versions.
    ///
    /// - Parameters:
    ///   - id: The shared transition identifier.
    ///   - namespace: The namespace used for matching source and destination.
    /// - Returns: The view with the matched transition source applied when available.
    @ViewBuilder
    func optionalMatchedTransitionSource<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID
    ) -> some View {
        if #available(iOS 18, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
    
    /// Conditionally applies a zoom navigation transition and does nothing on older OS versions.
    ///
    /// Use this on the **destination** view (e.g., sheet content) to create a zoom transition from a
    /// previously marked `matchedTransitionSource`.
    ///
    /// - Important:
    ///   This requires the same `sourceID` and `namespace` that were used on the source via
    ///   `optionalMatchedTransitionSource(id:in:)`. If they don't match (or the namespace is not stable),
    ///   SwiftUI will fall back to the default transition.
    ///
    /// - Parameters:
    ///   - sourceID: The shared transition identifier for the source view.
    ///   - namespace: The namespace used for matching source and destination.
    /// - Returns: The view with the navigation transition applied when available.
    @ViewBuilder
    func optionalZoomNavigationTransition<ID: Hashable>(
        sourceID: ID,
        in namespace: Namespace.ID
    ) -> some View {
        if #available(iOS 18, *) {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}
