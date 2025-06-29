//
//  NotificationService.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/5/15.
//

import Foundation
import UserNotifications
import AVFoundation

class NotificationService: NSObject {
    static let shared = NotificationService()
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            completion(granted)
            if let error = error {
                print("通知權限請求失敗: \(error.localizedDescription)")
            }
        }
    }
    
    func sendNotification(title: String, body: String, sound: UNNotificationSound = .default) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func announceStation(stopName: String, estimatedTime: String? = nil) {
        var announcement = "即將到達\(stopName)站"
        
        if let estimatedTime = estimatedTime {
            announcement += "，公車\(estimatedTime)"
        }
        
        let utterance = AVSpeechUtterance(string: announcement)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-TW")
        utterance.rate = 0.5
        utterance.volume = 1.0
        
        speechSynthesizer.speak(utterance)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // 前景也顯示通知
        completionHandler([.banner, .sound])
    }
}
