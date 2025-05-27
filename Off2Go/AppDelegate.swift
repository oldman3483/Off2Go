//
//  AppDelegate.swift
//  BusNotify
//
//  Created by Heidie Lee on 2025/5/15.
//

import UIKit
import CoreLocation
import UserNotifications

class AppDelegate: UIResponder, UIApplicationDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 請求通知權限
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("通知權限已獲准")
            } else if let error = error {
                print("通知權限請求失敗: \(error.localizedDescription)")
            }
        }
        
        return true
    }
    
    // 處理應用程序進入背景
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("應用程序進入背景")
    }
    
    // 處理應用程序返回前台
    func applicationWillEnterForeground(_ application: UIApplication) {
        print("應用程序返回前台")
    }
    
    // 允許在後台接收位置更新
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    // MARK: UISceneSession Lifecycle
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // 場景被丟棄時調用
    }
}
