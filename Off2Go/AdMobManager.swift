//
//  AdMobManager.swift
//  Off2Go
//
//  簡化版廣告管理服務 - 無測試設備設定
//

import Foundation
import GoogleMobileAds
import SwiftUI
import Combine

class AdMobManager: NSObject, ObservableObject {
    static let shared = AdMobManager()
    
    // 你的實際橫幅廣告 ID
    static let bannerAdUnitID = "ca-app-pub-9725234886980807/8400671487"
    
    @Published var isInitialized = false
    @Published var showAds = true // 控制是否顯示廣告
    
    // 廣告免費期間控制
    @Published var isAdFreeActive = false
    
    override init() {
        super.init()
        initializeAdMob()
        checkAdFreeStatus()
    }
    
    private func initializeAdMob() {
        print("🎯 [AdMob] 開始初始化 AdMob SDK")
        
        MobileAds.shared.start { [weak self] status in
            DispatchQueue.main.async {
                self?.isInitialized = true
                print("✅ [AdMob] AdMob SDK 初始化完成")
                print("📊 [AdMob] 適配器狀態: \(status.adapterStatusesByClassName)")
            }
        }
    }
    
    // 檢查廣告免費狀態
    private func checkAdFreeStatus() {
        if let adFreeUntil = UserDefaults.standard.object(forKey: "adFreeUntil") as? Date {
            isAdFreeActive = Date() < adFreeUntil
            
            if isAdFreeActive {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.dateStyle = .short
                print("🎁 [AdMob] 廣告免費期間至: \(formatter.string(from: adFreeUntil))")
            }
        } else {
            isAdFreeActive = false
        }
    }
    
    // 公開方法：檢查是否應該顯示廣告
    var shouldShowAds: Bool {
        return isInitialized && showAds && !isAdFreeActive
    }
    
    // 啟用廣告免費期間（可以作為將來獎勵功能的基礎）
    func activateAdFreeMode(duration: TimeInterval) {
        let adFreeUntil = Date().addingTimeInterval(duration)
        UserDefaults.standard.set(adFreeUntil, forKey: "adFreeUntil")
        checkAdFreeStatus()
        
        let hours = Int(duration / 3600)
        print("🎁 [AdMob] 啟用 \(hours) 小時廣告免費模式")
    }
    
    // 手動開關廣告（設定頁面可以使用）
    func toggleAds() {
        showAds.toggle()
        print("🔄 [AdMob] 廣告顯示切換為: \(showAds ? "開啟" : "關閉")")
    }
}
