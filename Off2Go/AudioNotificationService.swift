//
//  AudioNotificationService.swift - 簡化優化版
//  Off2Go
//
//  重構版本：簡化架構，修復背景語音問題
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import CoreLocation

class AudioNotificationService: NSObject, ObservableObject {
    static let shared = AudioNotificationService()
    
    // MARK: - 核心狀態
    @Published var isAudioEnabled: Bool = true
    @Published var isHeadphonesConnected: Bool = false
    @Published var currentDestination: String?
    @Published var targetStopName: String?
    
    // MARK: - 音頻核心
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()
    
    // MARK: - 設定
    private var _voiceLanguage: String = "zh-TW"
    private var _speechRate: Float = 0.5
    private var _speechVolume: Float = 1.0
    private var notificationDistance: Int = 2
    
    // MARK: - 防重複機制
    private var lastAnnouncementTime: [String: Date] = [:]
    private let minimumAnnouncementInterval: TimeInterval = 5.0
    private var isSpeaking: Bool = false
    
    // MARK: - 目的地追蹤
    private var destinationRoute: String?
    private var destinationStop: String?
    private var hasNotifiedApproaching = false
    private var hasNotifiedArrival = false
    
    // MARK: - 位置追蹤
    private var locationTrackingTimer: Timer?
    private var isTrackingActive = false
    
    override init() {
        super.init()
        setupAudioSession()
        setupHeadphoneDetection()
        setupSpeechDelegate()
        loadSettings()
        print("🔊 [Audio] AudioNotificationService 初始化完成")
    }
    
    // MARK: - 簡化的音頻設定
    
    private func setupAudioSession() {
        print("🔊 [Audio] 設定音頻會話...")
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // 檢查設備是否支援音頻播放
            let availableCategories = audioSession.availableCategories
            print("📱 [Audio] 可用音頻類別: \(availableCategories)")
            
            // 使用最相容的設定 - 改為 playAndRecord 以支援背景播放
            if availableCategories.contains(.playAndRecord) {
                try audioSession.setCategory(
                    .playAndRecord,
                    mode: .spokenAudio,
                    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
                )
            } else if availableCategories.contains(.playback) {
                try audioSession.setCategory(
                    .playback,
                    mode: .spokenAudio,
                    options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
                )
            } else {
                // 後備選項
                try audioSession.setCategory(.ambient)
            }
            
            // 設定音頻品質
            try audioSession.setPreferredSampleRate(44100.0)
            try audioSession.setPreferredIOBufferDuration(0.005)
            
            // 啟用會話
            try audioSession.setActive(true, options: [])
            print("✅ [Audio] 音頻會話設定成功")
            
        } catch let error as NSError {
            print("❌ [Audio] 音頻會話設定失敗: \(error.localizedDescription)")
            print("   錯誤代碼: \(error.code)")
            print("   錯誤域: \(error.domain)")
            
            // 嘗試簡化設定
            simplifiedAudioSetup()
        }
    }
    
    
    
    private func simplifiedAudioSetup() {
        print("🔄 [Audio] 嘗試簡化音頻設定...")
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // 最簡單的設定
            try audioSession.setCategory(.ambient)
            try audioSession.setActive(true)
            print("✅ [Audio] 簡化音頻設定成功")
            
        } catch {
            print("❌ [Audio] 簡化音頻設定也失敗: \(error.localizedDescription)")
            // 使用系統語音播報作為後備
            useFallbackSpeech()
        }
    }
    
    private func useFallbackSpeech() {
        print("🔄 [Audio] 使用後備語音播報方案")
        // 不依賴音頻會話的語音播報將在 executeSpeech 中處理
    }
    
    private func fallbackAudioSetup() {
        do {
            try audioSession.setCategory(.ambient)
            try audioSession.setActive(true)
            print("✅ [Audio] 備用音頻設定成功")
        } catch {
            print("❌ [Audio] 備用音頻設定失敗: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 統一的語音播報方法
    
    /// 等車提醒 - 最高優先級
    func announceWaitingBusAlert(_ message: String) {
        print("🚨 [Audio] 等車提醒: \(message)")
        
        // 立即播放系統提示音
        AudioServicesPlaySystemSound(1007) // 重要提醒音
        
        // 確保音頻會話準備就緒
        ensureAudioSessionForSpeech { [weak self] success in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // 無論音頻會話是否成功，都嘗試播報
                self.performSpeech(message, priority: .urgent, category: "waiting")
                
                // 如果第一次失敗，延遲後再試一次
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !self.speechSynthesizer.isSpeaking {
                        print("🔄 [Audio] 語音播報可能失敗，重試...")
                        
                        // 再次嘗試音頻設定
                        do {
                            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                            try AVAudioSession.sharedInstance().setActive(true)
                            
                            // 重新播報
                            self.performSpeech(message, priority: .urgent, category: "waiting_retry")
                        } catch {
                            print("❌ [Audio] 重試音頻設定失敗: \(error.localizedDescription)")
                            
                            // 最後手段：使用最簡單的設定
                            do {
                                try AVAudioSession.sharedInstance().setCategory(.ambient)
                                try AVAudioSession.sharedInstance().setActive(true)
                                self.performSpeech(message, priority: .urgent, category: "waiting_final")
                            } catch {
                                print("❌ [Audio] 所有音頻設定都失敗")
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// 到站提醒 - 高優先級
    func announceArrivalAlert(_ message: String) {
        print("🎯 [Audio] 到站提醒: \(message)")
        performSpeech(message, priority: .high, category: "arrival")
    }
    
    /// 接近目的地 - 高優先級
    func announceApproachingDestination(_ message: String) {
        print("🔔 [Audio] 接近提醒: \(message)")
        performSpeech(message, priority: .high, category: "approaching")
    }
    
    /// 一般站點資訊 - 普通優先級
    func announceStationInfo(stopName: String, arrivalTime: String? = nil) {
        let message = buildStationMessage(stopName: stopName, arrivalTime: arrivalTime)
        print("ℹ️ [Audio] 站點資訊: \(message)")
        performSpeech(message, priority: .normal, category: "station")
    }
    
    /// 測試語音播報
    func testVoicePlayback(_ message: String) {
        print("🧪 [Audio] 測試播報: \(message)")
        performSpeech(message, priority: .test, category: "test")
    }
    
    // MARK: - 核心語音播報邏輯
    
    private func performSpeech(_ message: String, priority: SpeechPriority, category: String) {
        guard isAudioEnabled || priority == .test || priority == .urgent else {
            print("🔇 [Audio] 語音已關閉，跳過播報")
            return
        }
        
        // 檢查重複播報
        if !canAnnounce(message, category: category, priority: priority) {
            return
        }
        
        // 確保音頻會話活躍
        ensureAudioSessionActive()
        
        // 停止當前播報（如果是更高優先級）
        if priority.rawValue >= SpeechPriority.high.rawValue && speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // 播放提示音（緊急情況）
        if priority == .urgent {
            AudioServicesPlaySystemSound(1007) // 重要提醒音
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.executeSpeech(message, priority: priority, category: category)
            }
        } else {
            executeSpeech(message, priority: priority, category: category)
        }
    }
    
    private func executeSpeech(_ message: String, priority: SpeechPriority, category: String) {
        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: _voiceLanguage)
        
        // 根據優先級設定語音參數
        switch priority {
        case .urgent:
            utterance.rate = 0.4
            utterance.volume = 1.0
            utterance.preUtteranceDelay = 0.1
        case .high:
            utterance.rate = 0.45
            utterance.volume = 0.9
            utterance.preUtteranceDelay = 0.2
        case .normal:
            utterance.rate = _speechRate
            utterance.volume = _speechVolume
            utterance.preUtteranceDelay = 0.3
        case .test:
            utterance.rate = 0.5
            utterance.volume = 1.0
            utterance.preUtteranceDelay = 0.1
        }
        
        // 記錄播報歷史
        updateAnnouncementHistory(message, category: category)
        
        // 在播報前嘗試確保音頻會話
        ensureAudioSessionForSpeech { [weak self] success in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                // 無論音頻會話是否成功，都嘗試播報
                self.speechSynthesizer.speak(utterance)
                self.isSpeaking = true
                print("🎤 [Audio] 開始播報: \(message)")
            }
        }
    }
    
    private func ensureAudioSessionForSpeech(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                
                // 檢查當前狀態
                let currentCategory = audioSession.category
                print("🔍 [Audio] 當前音頻類別: \(currentCategory)")
                
                // 強制設定為播放類別
                if currentCategory != .playAndRecord && currentCategory != .playback {
                    try audioSession.setCategory(
                        .playAndRecord,
                        mode: .spokenAudio,
                        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
                    )
                }
                
                // 重新啟用會話（這會覆蓋之前的狀態）
                try audioSession.setActive(true, options: [])
                
                print("✅ [Audio] 語音播報音頻會話準備成功")
                DispatchQueue.main.async {
                    completion(true)
                }
                
            } catch {
                print("⚠️ [Audio] 語音播報音頻會話準備失敗: \(error.localizedDescription)")
                
                // 嘗試基本設定
                do {
                    try AVAudioSession.sharedInstance().setCategory(.ambient)
                    try AVAudioSession.sharedInstance().setActive(true)
                    print("✅ [Audio] 使用基本音頻設定")
                    DispatchQueue.main.async {
                        completion(true)
                    }
                } catch {
                    print("❌ [Audio] 基本音頻設定也失敗: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(false)
                    }
                }
            }
        }
    }
    
    // MARK: - 重複播報檢查
    
    private func canAnnounce(_ content: String, category: String, priority: SpeechPriority) -> Bool {
        let key = "\(category)_\(content)"
        let now = Date()
        
        // 緊急和測試播報總是允許
        if priority == .urgent || priority == .test {
            return true
        }
        
        // 檢查是否正在播報
        if isSpeaking && priority.rawValue < SpeechPriority.high.rawValue {
            print("🔇 [Audio] 正在播報中，跳過低優先級內容")
            return false
        }
        
        // 檢查重複間隔
        if let lastTime = lastAnnouncementTime[key],
           now.timeIntervalSince(lastTime) < minimumAnnouncementInterval {
            print("🔇 [Audio] 重複內容間隔過短，跳過播報")
            return false
        }
        
        return true
    }
    
    private func updateAnnouncementHistory(_ content: String, category: String) {
        let key = "\(category)_\(content)"
        lastAnnouncementTime[key] = Date()
    }
    
    // MARK: - 音頻會話管理
    
    private func ensureAudioSessionActive() {
        print("🔍 [Audio] 檢查音頻會話狀態")
    }
    
    // MARK: - 目的地管理
    
    func setDestination(_ routeName: String, stopName: String) {
        print("🎯 [Audio] 設定目的地: \(routeName) - \(stopName)")
        
        destinationRoute = routeName
        destinationStop = stopName
        targetStopName = stopName
        currentDestination = routeName.isEmpty ? stopName : "\(routeName) - \(stopName)"
        
        hasNotifiedApproaching = false
        hasNotifiedArrival = false
        
        startLocationTracking()
        
        let message = "目的地已設定為\(stopName)，將在接近時提醒您"
        performSpeech(message, priority: .normal, category: "destination")
        
        updateNowPlayingInfo(with: "追蹤中")
    }
    
    func clearDestination() {
        print("🗑️ [Audio] 清除目的地")
        
        let hadDestination = destinationRoute != nil || destinationStop != nil
        
        destinationRoute = nil
        destinationStop = nil
        targetStopName = nil
        currentDestination = nil
        hasNotifiedApproaching = false
        hasNotifiedArrival = false
        
        stopLocationTracking()
        
        if hadDestination {
            let message = "目的地已取消"
            performSpeech(message, priority: .normal, category: "destination")
        }
        
        updateNowPlayingInfo(with: "待機中")
    }
    
    // MARK: - 位置追蹤
    
    private func startLocationTracking() {
        guard LocationService.shared.hasLocationPermission else {
            print("⚠️ [Audio] 需要位置權限才能開始追蹤")
            return
        }
        
        stopLocationTracking()
        LocationService.shared.startUpdatingLocation()
        
        locationTrackingTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.checkLocationForDestination()
        }
        
        isTrackingActive = true
        print("📍 [Audio] 已開始位置追蹤")
    }
    
    private func stopLocationTracking() {
        locationTrackingTimer?.invalidate()
        locationTrackingTimer = nil
        isTrackingActive = false
        LocationService.shared.stopUpdatingLocation()
        print("🛑 [Audio] 已停止位置追蹤")
    }
    
    private func checkLocationForDestination() {
        guard let targetStop = destinationStop,
              let userLocation = LocationService.shared.currentLocation else {
            return
        }
        
        print("📍 [Audio] 檢查位置：距離目的地計算中...")
    }
    
    func checkDestinationProximity(currentStops: [BusStop.Stop], userLocation: CLLocation) {
        guard isTrackingActive,
              let targetStop = destinationStop else {
            return
        }
        
        guard let destinationStopData = currentStops.first(where: { $0.StopName.Zh_tw.contains(targetStop) }) else {
            return
        }
        
        let stopLocation = CLLocation(
            latitude: destinationStopData.StopPosition.PositionLat,
            longitude: destinationStopData.StopPosition.PositionLon
        )
        
        let distance = userLocation.distance(from: stopLocation)
        print("📏 [Audio] 距離目的地 \(Int(distance)) 公尺")
        
        if distance <= 100 && !hasNotifiedArrival {
            announceArrivalAtDestination()
            hasNotifiedArrival = true
        } else if distance <= 300 && !hasNotifiedApproaching {
            announceApproachingDestination(distance: Int(distance))
            hasNotifiedApproaching = true
        }
    }
    
    private func announceApproachingDestination(distance: Int) {
        guard let targetStop = destinationStop else { return }
        let message = "提醒您，即將到達\(targetStop)，距離約\(distance)公尺，請準備下車"
        announceApproachingDestination(message)
        updateNowPlayingInfo(with: "即將到站")
    }
    
    private func announceArrivalAtDestination() {
        guard let targetStop = destinationStop else { return }
        let message = "\(targetStop)到了，請準備下車"
        announceArrivalAlert(message)
        updateNowPlayingInfo(with: "已到達")
    }
    
    // MARK: - 音頻設定方法
    
    func toggleAudioNotifications() {
        isAudioEnabled.toggle()
        saveSettings()
        
        let message = isAudioEnabled ? "語音提醒開啟" : "語音提醒關閉"
        performSpeech(message, priority: .normal, category: "settings")
        updateNowPlayingInfo()
    }
    
    func setSpeechRate(_ rate: Float) {
        _speechRate = max(0.1, min(1.0, rate))
        saveSettings()
    }
    
    func setSpeechVolume(_ volume: Float) {
        _speechVolume = max(0.1, min(1.0, volume))
        saveSettings()
    }
    
    func setVoiceLanguage(_ language: String) {
        _voiceLanguage = language
        saveSettings()
    }
    
    // MARK: - 輔助方法
    
    private func buildStationMessage(stopName: String, arrivalTime: String?) -> String {
        var message = "即將到達\(stopName)"
        
        if let time = arrivalTime, !time.isEmpty, time != message {
            message += "，\(time)"
        }
        
        return message
    }
    
    private func setupHeadphoneDetection() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        checkHeadphoneConnection()
    }
    
    @objc private func audioRouteChanged(notification: Notification) {
        checkHeadphoneConnection()
    }
    
    private func checkHeadphoneConnection() {
        let currentRoute = audioSession.currentRoute
        var headphonesConnected = false
        
        for output in currentRoute.outputs {
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                headphonesConnected = true
                break
            default:
                break
            }
        }
        
        DispatchQueue.main.async {
            self.isHeadphonesConnected = headphonesConnected
        }
    }
    
    private func setupSpeechDelegate() {
        speechSynthesizer.delegate = self
    }
    
    private func updateNowPlayingInfo(with status: String = "待機中") {
        var nowPlayingInfo = [String: Any]()
        
        if let destination = currentDestination {
            nowPlayingInfo[MPMediaItemPropertyTitle] = "Off2Go 到站提醒"
            nowPlayingInfo[MPMediaItemPropertyArtist] = destination
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = status
        } else {
            nowPlayingInfo[MPMediaItemPropertyTitle] = "Off2Go"
            nowPlayingInfo[MPMediaItemPropertyArtist] = "公車到站提醒"
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = status
        }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isTrackingActive ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // MARK: - 持久化
    
    private func saveSettings() {
        UserDefaults.standard.set(isAudioEnabled, forKey: "audioEnabled")
        UserDefaults.standard.set(notificationDistance, forKey: "notificationDistance")
        UserDefaults.standard.set(_speechRate, forKey: "speechRate")
        UserDefaults.standard.set(_speechVolume, forKey: "speechVolume")
        UserDefaults.standard.set(_voiceLanguage, forKey: "voiceLanguage")
    }
    
    private func loadSettings() {
        isAudioEnabled = UserDefaults.standard.bool(forKey: "audioEnabled")
        if !UserDefaults.standard.objectExists(forKey: "audioEnabled") {
            isAudioEnabled = true // 預設開啟
        }
        
        notificationDistance = UserDefaults.standard.integer(forKey: "notificationDistance")
        _speechRate = UserDefaults.standard.float(forKey: "speechRate")
        _speechVolume = UserDefaults.standard.float(forKey: "speechVolume")
        _voiceLanguage = UserDefaults.standard.string(forKey: "voiceLanguage") ?? "zh-TW"
        
        if notificationDistance == 0 { notificationDistance = 2 }
        if _speechRate == 0 { _speechRate = 0.5 }
        if _speechVolume == 0 { _speechVolume = 1.0 }
    }
    
    func resetNotificationStatus() {
        lastAnnouncementTime.removeAll()
        hasNotifiedApproaching = false
        hasNotifiedArrival = false
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        
        print("🔄 [Audio] 已重置音頻通知狀態")
    }
    
    // MARK: - 屬性訪問器
    
    var voiceLanguage: String { _voiceLanguage }
    var speechRate: Float { _speechRate }
    var speechVolume: Float { _speechVolume }
    
    deinit {
        stopLocationTracking()
        NotificationCenter.default.removeObserver(self)
        speechSynthesizer.stopSpeaking(at: .immediate)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AudioNotificationService: AVSpeechSynthesizerDelegate {
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("🎤 [Audio] 開始播報: \(utterance.speechString)")
        isSpeaking = true
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("✅ [Audio] 播報完成: \(utterance.speechString)")
        isSpeaking = false
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("🛑 [Audio] 播報被取消: \(utterance.speechString)")
        isSpeaking = false
    }
}

// MARK: - 語音優先級

private enum SpeechPriority: Int, CaseIterable {
    case normal = 1
    case high = 2
    case urgent = 3
    case test = 4
}

// MARK: - UserDefaults 擴展

extension UserDefaults {
    func objectExists(forKey key: String) -> Bool {
        return object(forKey: key) != nil
    }
}
