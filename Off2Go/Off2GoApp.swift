//
//  Off2GoApp.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/5/27.
//

import SwiftUI
import UserNotifications

@main
struct Off2GoApp: App {
    // 创建共享的服务实例
    @StateObject private var locationService = LocationService.shared
    @StateObject private var audioService = AudioNotificationService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationService)
                .environmentObject(audioService)
                .onAppear {
                    // 请求权限
                    locationService.requestLocationPermission()
                    
                    // 请求通知权限
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                        if granted {
                            print("通知权限已获得")
                        } else if let error = error {
                            print("通知权限请求失败: \(error.localizedDescription)")
                        }
                    }
                }
        }
    }
}
