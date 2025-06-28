//
//  AppDelegate.swift - 優化版
//  Off2Go
//
//  簡化背景音頻設定，專注於核心功能
//

import UIKit
import CoreLocation
import UserNotifications
import AVFoundation

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // 設定通知權限
        setupNotificationPermissions()
        
        return true
    }
    
    // MARK: - 通知權限設定
    
    private func setupNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("✅ [AppDelegate] 通知權限已獲得")
                } else {
                    print("❌ [AppDelegate] 通知權限被拒絕")
                    if let error = error {
                        print("   錯誤: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // 設定通知類別
        setupNotificationCategories()
    }
    
    private func setupNotificationCategories() {
        let busAlertCategory = UNNotificationCategory(
            identifier: "BUS_ALERT",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([busAlertCategory])
    }
    
    private func simplifiedAudioSetup() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // 使用最相容的設定
            try audioSession.setCategory(.ambient)
            try audioSession.setActive(true)
            print("✅ [AppDelegate] 簡化音頻設定成功")
        } catch {
            print("❌ [AppDelegate] 簡化音頻設定失敗: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 應用程式生命週期
    
    func applicationDidEnterBackground(_ application: UIApplication) {
            print("📱 [AppDelegate] 應用程式進入背景")
            
            // 重置音頻服務狀態（但不設定音頻會話）
            AudioNotificationService.shared.resetNotificationStatus()
            
            // 開始背景任務（給語音播報更多時間）
            var backgroundTask: UIBackgroundTaskIdentifier = .invalid
            backgroundTask = application.beginBackgroundTask(withName: "AudioNotificationTask") {
                print("⏰ [AppDelegate] 背景任務即將結束")
                application.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
            
            // 60秒後結束背景任務
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                if backgroundTask != .invalid {
                    application.endBackgroundTask(backgroundTask)
                    backgroundTask = .invalid
                }
            }
        }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        print("📱 [AppDelegate] 應用程式返回前台")

        // 重置音頻服務狀態
        AudioNotificationService.shared.resetNotificationStatus()
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        print("📱 [AppDelegate] 應用程式變為活躍")
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        print("📱 [AppDelegate] 應用程式即將失去活躍狀態")
    }
    
    // MARK: - UISceneSession Lifecycle
    
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // 場景被丟棄時調用
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
