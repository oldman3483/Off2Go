//
//  SkyBlueAppIconView.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/6/28.
//

import SwiftUI

// Color 擴展，用於支援 hex 顏色
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct SkyBlueAppIconView: View {
    var body: some View {
        ZStack {
            // 天空藍背景漸層
            LinearGradient(
                colors: [Color(hex: "67E8F9"), Color(hex: "06B6D4")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // 公車圖示 (放大)
            Text("🚌")
                .font(.system(size: 75))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 2)
            
            // 鈴鐺徽章 - 太陽色系
            VStack {
                HStack {
                    Spacer()
                    ZStack {
                        // 外層陰影
                        Circle()
                            .fill(Color.black.opacity(0.2))
                            .frame(width: 37, height: 37)
                            .offset(x: 1, y: 1.5)
                        
                        // 太陽般的金黃色
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(hex: "FDE047"),
                                        Color(hex: "F59E0B"),
                                        Color(hex: "D97706")
                                    ],
                                    center: .topLeading,
                                    startRadius: 2,
                                    endRadius: 20
                                )
                            )
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(
                                        Color.white.opacity(0.7),
                                        lineWidth: 1.5
                                    )
                            )
                        
                        // 鈴鐺圖示
                        Image(systemName: "bell.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.6), radius: 1, x: 0, y: 1)
                    }
                    .padding(.trailing, 7)
                }
                .padding(.top, 7)
                Spacer()
            }
        }
        .frame(width: 120, height: 120)
        .clipped()
    }
}

// 預覽
#Preview {
    VStack(spacing: 20) {
        SkyBlueAppIconView()
        
        Text("Off2Go App 圖示")
            .font(.title2)
            .fontWeight(.semibold)
    }
    .padding()
}
