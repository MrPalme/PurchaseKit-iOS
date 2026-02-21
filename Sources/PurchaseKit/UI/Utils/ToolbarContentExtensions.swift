//
//  ToolbarContentExtensions.swift
//  PurchaseKit
//
//  Created by Markus Mock on 17.02.26.
//

import SwiftUI

// MARK: - iOS 26 Navigation Transition Compatibility

public extension ToolbarContent {
    
    /// Conditionally applies a matched transition source (iOS 26+) and does nothing on older OS versions.
    ///
    /// - Parameters:
    ///   - id: The shared transition identifier.
    ///   - namespace: The namespace used for matching source and destination.
    /// - Returns: The view with the matched transition source applied when available.
    @ToolbarContentBuilder
    func optionalMatchedTransitionSource<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID
    ) -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
