//
//  String+Domain.swift
//  ShootMap
//
//  Created by Septuagint Murito on 8/15/26.
//

import Foundation

nonisolated extension String {
    /// Whitespace/newline-trimmed copy.
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Trimmed copy, or `nil` when the result would be empty.
    nonisolated var trimmedNonEmpty: String? { trimmed.isEmpty ? nil : trimmed }
}
