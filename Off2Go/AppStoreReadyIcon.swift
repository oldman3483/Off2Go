//
//  AppStoreReadyIcon.swift
//  Off2Go
//
//  專為 App Store 優化的圖示版本
//

import SwiftUI

struct AppStoreReadyIconView: View {
    let size: CGFloat
    
    init(size: CGFloat = 120) {
        self.size = size
    }
    
    var body: some View {
        ZStack {
            // 天空藍背景漸層
            LinearGradient(
                colors: [Color("67E8F9"), Color("06B6D4")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // 公車圖示 - 確保在小尺寸下也清晰可見
            Text("🚌")
                .font(.system(size: size * 0.6, weight: .medium, design: .default))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: size * 0.015, x: 0, y: size * 0.008)
            
            // 鈴鐺徽章 - 在小尺寸時調整位置和大小
            VStack {
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color("FBBF24"))
                            .frame(width: max(16, size * 0.32), height: max(16, size * 0.32))
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: max(1.5, size * 0.02))
                            )
                            .shadow(color: .black.opacity(0.2), radius: size * 0.015, x: 0, y: size * 0.008)
                        
                        // 對於非常小的尺寸，使用簡化的圖示
                        if size >= 40 {
                            Text("🔔")
                                .font(.system(size: max(8, size * 0.15)))
                                .grayscale(1.0)
                                .brightness(0.0)
                                .colorInvert()
                        } else {
                            Circle()
                                .fill(Color.white)
                                .frame(width: size * 0.08, height: size * 0.08)
                        }
                    }
                    .padding(.trailing, max(4, size * 0.08))
                }
                .padding(.top, max(4, size * 0.08))
                Spacer()
            }
        }
        .frame(width: size, height: size)
        // App 圖示不需要圓角，iOS 會自動添加
        .clipped()
    }
}
