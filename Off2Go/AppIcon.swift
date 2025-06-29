////
////  AppIcon.swift - 合併優化版
////  Off2Go
////
//
//import SwiftUI
//
//struct AppIconView: View {
//    let size: CGFloat
//    let isForAppStore: Bool
//    
//    init(size: CGFloat = 120, isForAppStore: Bool = false) {
//        self.size = size
//        self.isForAppStore = isForAppStore
//    }
//    
//    var body: some View {
//        ZStack {
//            // 天空藍背景漸層
//            LinearGradient(
//                colors: [Color(hex: "67E8F9"), Color(hex: "06B6D4")],
//                startPoint: .topLeading,
//                endPoint: .bottomTrailing
//            )
//            
//            // 公車圖示
//            Text("🚌")
//                .font(.system(size: size * 0.6))
//                .foregroundColor(.white)
//                .shadow(color: .black.opacity(0.25), radius: size * 0.015, x: 0, y: size * 0.008)
//            
//            // 鈴鐺徽章
//            VStack {
//                HStack {
//                    Spacer()
//                    ZStack {
//                        Circle()
//                            .fill(Color(hex: "FBBF24"))
//                            .frame(width: max(16, size * 0.32), height: max(16, size * 0.32))
//                            .overlay(
//                                Circle()
//                                    .stroke(Color.white, lineWidth: max(1.5, size * 0.02))
//                            )
//                            .shadow(color: .black.opacity(0.2), radius: size * 0.015, x: 0, y: size * 0.008)
//                        
//                        if size >= 40 {
//                            Text("🔔")
//                                .font(.system(size: max(8, size * 0.15)))
//                                .grayscale(1.0)
//                                .brightness(0.0)
//                                .colorInvert()
//                        } else {
//                            Circle()
//                                .fill(Color.white)
//                                .frame(width: size * 0.08, height: size * 0.08)
//                        }
//                    }
//                    .padding(.trailing, max(4, size * 0.08))
//                }
//                .padding(.top, max(4, size * 0.08))
//                Spacer()
//            }
//        }
//        .frame(width: size, height: size)
//        .clipped()
//    }
//}
//
//// Color 擴展
//extension Color {
//    init(hex: String) {
//        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
//        var int: UInt64 = 0
//        Scanner(string: hex).scanHexInt64(&int)
//        let a, r, g, b: UInt64
//        switch hex.count {
//        case 3:
//            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
//        case 6:
//            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
//        case 8:
//            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
//        default:
//            (a, r, g, b) = (1, 1, 1, 0)
//        }
//
//        self.init(
//            .sRGB,
//            red: Double(r) / 255,
//            green: Double(g) / 255,
//            blue:  Double(b) / 255,
//            opacity: Double(a) / 255
//        )
//    }
//}
//
//// 預覽用的別名
//typealias SkyBlueAppIconView = AppIconView
