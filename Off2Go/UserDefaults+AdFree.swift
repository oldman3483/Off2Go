//
//  UserDefaults+AdFree.swift
//  Off2Go
//

import Foundation

extension UserDefaults {
    var isAdFree: Bool {
        guard let adFreeUntil = object(forKey: "adFreeUntil") as? Date else {
            return false
        }
        return Date() < adFreeUntil
    }
}
