//
//  BannerAdView.swift
//  Off2Go
//
//  橫幅廣告組件 - 修正版本
//

import SwiftUI
import GoogleMobileAds

struct BannerAdView: UIViewRepresentable {
    let adSize: AdSize
    
    init(adSize: AdSize = AdSizeBanner) {
        self.adSize = adSize
    }
    
    func makeUIView(context: Context) -> BannerView {
        let bannerView = BannerView(adSize: adSize)
        bannerView.adUnitID = AdMobManager.bannerAdUnitID
        bannerView.delegate = context.coordinator
        
        // 獲取根視圖控制器
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            bannerView.rootViewController = rootViewController
        }
        
        let request = Request()
        bannerView.load(request)
        
        return bannerView
    }
    
    func updateUIView(_ uiView: BannerView, context: Context) {
        // 不需要更新
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("✅ [AdMob] Banner 廣告載入成功")
        }
        
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("❌ [AdMob] Banner 廣告載入失敗: \(error.localizedDescription)")
        }
        
        func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            print("👀 [AdMob] Banner 廣告曝光記錄")
        }
        
        func bannerViewWillPresentScreen(_ bannerView: BannerView) {
            print("📱 [AdMob] Banner 廣告即將打開")
        }
        
        func bannerViewDidDismissScreen(_ bannerView: BannerView) {
            print("📱 [AdMob] Banner 廣告已關閉")
        }
    }
}

// 智慧型橫幅廣告組件
struct SmartBannerAdView: View {
    @EnvironmentObject var adMobManager: AdMobManager
    
    var body: some View {
        Group {
            if adMobManager.shouldShowAds {
                BannerAdView()
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [Color(.systemGray6), Color(.systemGray5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
        }
    }
}

// 自適應橫幅廣告組件
struct AdaptiveBannerAdView: UIViewRepresentable {
    
    func makeUIView(context: Context) -> BannerView {
        // 創建自適應廣告尺寸
        let viewWidth = UIScreen.main.bounds.width
        let adaptiveSize = currentOrientationAnchoredAdaptiveBanner(width: viewWidth)
        
        let bannerView = BannerView(adSize: adaptiveSize)
        bannerView.adUnitID = AdMobManager.bannerAdUnitID
        bannerView.delegate = context.coordinator
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            bannerView.rootViewController = rootViewController
        }
        
        let request = Request()
        bannerView.load(request)
        
        return bannerView
    }
    
    func updateUIView(_ uiView: BannerView, context: Context) {}
    
    func makeCoordinator() -> BannerAdView.Coordinator {
        BannerAdView.Coordinator()
    }
}
