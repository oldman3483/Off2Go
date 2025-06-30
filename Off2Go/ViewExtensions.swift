//
//  ViewExtensions.swift
//  Off2Go
//
//  iOS 版本相容性擴展
//

import SwiftUI

extension View {
    /// iOS 17 相容的 onChange 修飾符 - 無參數版本
    @ViewBuilder
    func compatibleOnChange<T: Equatable>(of value: T, perform action: @escaping () -> Void) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) {
                action()
            }
        } else {
            self.onChange(of: value) { _ in
                action()
            }
        }
    }
    
    /// iOS 17 相容的 onChange 修飾符 - 單參數版本（新值）
    @ViewBuilder
    func compatibleOnChange<T: Equatable>(of value: T, perform action: @escaping (T) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { oldValue, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value) { newValue in
                action(newValue)
            }
        }
    }
    
    /// iOS 17 相容的 onChange 修飾符 - 雙參數版本（舊值和新值）
    @ViewBuilder
    func compatibleOnChange<T: Equatable>(of value: T, perform action: @escaping (T, T) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { oldValue, newValue in
                action(oldValue, newValue)
            }
        } else {
            self.onChange(of: value) { newValue in
                // 在舊版本中，我們無法獲取舊值，所以傳入相同的值
                action(newValue, newValue)
            }
        }
    }
}
