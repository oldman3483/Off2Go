//
//  AudioNotificationService.swift - 音量恢復優化版
//  Off2Go
//
//  修復：避免設定等車提醒時立即影響音樂音量
//

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import CoreLocation

class AudioNotificationService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AudioNotificationService()
    
    // MARK: - 核心狀態
    @Published var isAudioEnabled: Bool = true
    @Published var isHeadphonesConnected: Bool = false
    @Published var currentDestination: String?
    @Published var targetStopName: String?
    
    // MARK: - 智慧音頻設定
    @Published var smartVolumeEnabled: Bool = true
    @Published var videoModeEnabled: Bool = true
    @Published var duckingLevel: Float = 0.3
    @Published var overlayVolumeBoost: Float = 0.2
    
    // MARK: - 音頻核心
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()
    
    // MARK: - 修正：音頻會話管理狀態（新增原始音量恢復）
    private var originalAudioCategory: AVAudioSession.Category?
    private var originalAudioOptions: AVAudioSession.CategoryOptions?
    private var originalSystemVolume: Float = 1.0  // 新增：記錄原始系統音量
    private var hasStoredOriginalSettings = false
    private var audioSessionConfigured = false
    private var shouldRestoreVolume = false  // 新增：標記是否需要恢復音量
    
    // MARK: - 音頻狀態管理
    private var originalVolume: Float = 1.0
    private var wasOtherAudioPlaying = false
    private var audioMixState: AudioMixState = .normal
    private var currentAudioApp: String?
    private var isInterrupted = false
    
    // MARK: - 音頻混合狀態
    private enum AudioMixState {
        case normal
        case smartDucking
        case videoOverlay
        case musicDucking
        case podcastPause
        case gameAudioMix
    }
    
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
        setupHeadphoneDetection()
        setupSpeechDelegate()
        setupAudioInterruptionHandling()
        startAudioEnvironmentMonitoring()
        loadSettings()
        print("🔊 [Audio] AudioNotificationService 初始化完成（非侵入式）")
    }
    
    // MARK: - 修正：按需音頻會話設定（僅在播報時設定）
    
    private func prepareAudioSessionForSpeechOnly() {
        guard !audioSessionConfigured else {
            print("🔊 [Audio] 音頻會話已設定，跳過重複設定")
            return
        }
        
        print("🔊 [Audio] === 準備語音播報音頻會話 ===")
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // 儲存原始設定（只在第一次設定時）
            if !hasStoredOriginalSettings {
                originalAudioCategory = audioSession.category
                originalAudioOptions = audioSession.categoryOptions
                
                // 新增：記錄原始系統音量
                originalSystemVolume = AVAudioSession.sharedInstance().outputVolume
                
                hasStoredOriginalSettings = true
                print("📦 [Audio] 已儲存原始音頻設定: \(originalAudioCategory?.rawValue ?? "未知")")
                print("🔊 [Audio] 已儲存原始系統音量: \(originalSystemVolume)")
            }
            
            // 更智慧的音頻播放狀態檢測
            let isOtherAudioPlaying = detectOtherAudioPlaying()
            wasOtherAudioPlaying = isOtherAudioPlaying
            
            print("🎵 [Audio] 其他音頻播放狀態: \(isOtherAudioPlaying)")
            
            // 修正：總是使用混音模式，避免中斷音樂
            if isOtherAudioPlaying && smartVolumeEnabled {
                // 有其他音頻且開啟智慧音量：使用降音混音
                try audioSession.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
                print("🎵 [Audio] 使用智慧降音混音模式")
                shouldRestoreVolume = true
            } else {
                // 預設使用非侵入式混音（不會中斷任何音頻）
                try audioSession.setCategory(.ambient, options: [.mixWithOthers])
                print("🎵 [Audio] 使用非侵入式混音模式（預設安全模式）")
                shouldRestoreVolume = false
            }
            
            try audioSession.setActive(true)
            audioSessionConfigured = true
            
            print("✅ [Audio] 語音播報音頻會話設定完成")
            
        } catch {
            print("❌ [Audio] 語音播報音頻會話設定失敗: \(error.localizedDescription)")
            
            // 備用方案：使用最安全的設定
            do {
                try audioSession.setCategory(.ambient, options: [.mixWithOthers])
                try audioSession.setActive(true)
                audioSessionConfigured = true
                shouldRestoreVolume = false
                print("✅ [Audio] 使用備用安全音頻設定")
            } catch {
                print("❌ [Audio] 備用音頻設定也失敗: \(error.localizedDescription)")
            }
        }
    }
    
    // 新增：更準確的音頻播放狀態檢測
    private func detectOtherAudioPlaying() -> Bool {
        let audioSession = AVAudioSession.sharedInstance()
        
        // 方法1：檢查系統狀態
        let systemDetection = audioSession.isOtherAudioPlaying
        
        // 方法2：檢查 Now Playing 資訊
        let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        let hasNowPlayingInfo = nowPlayingInfo != nil && !nowPlayingInfo!.isEmpty
        
        // 方法3：檢查音頻輸出路由（某些情況下可以推測）
        let currentRoute = audioSession.currentRoute
        let hasAudioOutput = !currentRoute.outputs.isEmpty
        
        print("🔍 [Audio] 音頻檢測詳情:")
        print("   系統檢測: \(systemDetection)")
        print("   Now Playing 資訊: \(hasNowPlayingInfo)")
        print("   音頻輸出: \(hasAudioOutput)")
        
        // 更保守的判斷：如果有任何跡象顯示可能有音頻，就認為有
        let finalResult = systemDetection || hasNowPlayingInfo
        
        print("   最終判斷: \(finalResult)")
        
        return finalResult
    }
    
    private func restoreOriginalAudioSession() {
        guard audioSessionConfigured else {
            print("🔊 [Audio] 音頻會話未設定，無需恢復")
            return
        }
        
        // 延遲恢復，避免頻繁的音頻會話切換
        print("🔄 [Audio] === 延遲恢復音頻設定（減少音樂中斷）===")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { // 延遲2秒恢復
            do {
                let audioSession = AVAudioSession.sharedInstance()
                
                // 溫和的恢復：使用 notifyOthersOnDeactivation 讓其他音頻自然恢復
                try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
                
                // 短暫延遲後恢復到安全設定
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    do {
                        // 永遠使用安全的混音設定，不恢復到可能中斷音頻的原始設定
                        try audioSession.setCategory(.ambient, options: [.mixWithOthers])
                        try audioSession.setActive(true)
                        print("✅ [Audio] 溫和恢復到安全混音設定")
                    } catch {
                        print("ℹ️ [Audio] 系統音頻會話由 iOS 自動管理")
                    }
                }
                
                self.audioSessionConfigured = false
                self.shouldRestoreVolume = false
                
                print("✅ [Audio] 音頻設定溫和恢復完成")
                
            } catch {
                print("ℹ️ [Audio] 音頻會話由系統自動管理")
                self.audioSessionConfigured = false
                self.shouldRestoreVolume = false
            }
        }
    }
    
    // MARK: - 智慧音頻環境分析
    
    private func analyzeCurrentAudioEnvironment() -> AudioEnvironment {
        let audioSession = AVAudioSession.sharedInstance()
        let isOtherAudioPlaying = audioSession.isOtherAudioPlaying
        
        guard isOtherAudioPlaying else {
            return .silent
        }
        
        // 分析正在播放的音頻類型
        let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        
        // 檢查應用程式類型
        if let artist = nowPlayingInfo?[MPMediaItemPropertyArtist] as? String {
            currentAudioApp = artist
            
            // 影片應用程式
            let videoApps = ["YouTube", "Netflix", "Disney+", "Prime Video", "HBO",
                             "Apple TV", "影片", "Video", "TikTok", "Instagram"]
            if videoApps.contains(where: { artist.contains($0) }) {
                return .video
            }
            
            // 播客/有聲書應用程式
            let podcastApps = ["Podcasts", "Apple Podcasts", "Overcast",
                               "播客", "有聲書", "Audible"]
            if podcastApps.contains(where: { artist.contains($0) }) {
                return .podcast
            }
        }
        
        // 檢查媒體類型
        if let mediaType = nowPlayingInfo?[MPMediaItemPropertyMediaType] as? NSNumber {
            let type = MPMediaType(rawValue: mediaType.uintValue)
            if type.contains(.movie) || type.contains(.tvShow) || type.contains(.videoITunesU) {
                return .video
            }
            if type.contains(.podcast) || type.contains(.audioBook) {
                return .podcast
            }
        }
        
        // 預設為音樂
        return .music
    }
    
    private enum AudioEnvironment {
        case silent
        case music
        case video
        case podcast
        case game
    }
    
    // MARK: - 音頻中斷處理
    
    private func setupAudioInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }
    
    @objc private func handleAudioInterruption(notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            print("🔇 [Audio] 音頻中斷開始")
            isInterrupted = true
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.pauseSpeaking(at: .immediate)
            }
            
        case .ended:
            print("🔊 [Audio] 音頻中斷結束")
            
            // 修正：更快速的中斷恢復
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isInterrupted = false
                print("✅ [Audio] 中斷狀態已重置")
            }
            
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // 延遲恢復，避免立即衝突
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if self.speechSynthesizer.isPaused {
                            self.speechSynthesizer.continueSpeaking()
                        }
                    }
                }
            }
            
        @unknown default:
            break
        }
    }
    
    @objc private func handleMediaServicesReset() {
        print("🔄 [Audio] 媒體服務重置")
        audioSessionConfigured = false
        isInterrupted = false
        shouldRestoreVolume = false
    }
    
    // MARK: - 統一的語音播報方法
    
    /// 等車提醒 - 最高優先級（修正：忽略中斷狀態）
    func announceWaitingBusAlert(_ message: String) {
        print("🚨 [Audio] 等車提醒: \(message)")
        
        // 播放更有趣的提示音
        AudioServicesPlaySystemSound(1016) // 使用更活潑的系統音效
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let friendlyMessage = "\(message)"
            self.performSpeech(friendlyMessage, priority: .urgent, category: "waiting")
        }
    }
    
    /// 到站提醒 - 高優先級
    func announceArrivalAlert(_ message: String) {
        print("🎯 [Audio] 到站提醒: \(message)")
        let friendlyMessage = "到站了！\(message)"
        performSpeech(friendlyMessage, priority: .high, category: "arrival")
    }
    
    /// 接近目的地 - 高優先級
    func announceApproachingDestination(_ message: String) {
        print("🔔 [Audio] 接近提醒: \(message)")
        let friendlyMessage = "快到了！\(message)"
        performSpeech(friendlyMessage, priority: .high, category: "approaching")
    }
    
    /// 一般站點資訊 - 普通優先級
    func announceStationInfo(stopName: String, arrivalTime: String? = nil) {
        let message = buildStationMessage(stopName: stopName, arrivalTime: arrivalTime)
        print("ℹ️ [Audio] 站點資訊: \(message)")
        performSpeech(message, priority: .normal, category: "station")
    }
    
    // MARK: - 智慧音頻設定方法
    
    func toggleSmartVolume() {
        smartVolumeEnabled.toggle()
        saveSettings()
        
        let message = smartVolumeEnabled ? "智慧音量調整已開啟" : "智慧音量調整已關閉"
        performSpeech(message, priority: .normal, category: "settings")
    }
    
    func toggleVideoMode() {
        videoModeEnabled.toggle()
        saveSettings()
        
        let message = videoModeEnabled ? "影片模式已開啟" : "影片模式已關閉"
        performSpeech(message, priority: .normal, category: "settings")
    }
    
    func setDuckingLevel(_ level: Float) {
        duckingLevel = max(0.1, min(0.7, level))
        saveSettings()
        print("🔉 [Audio] 降音程度設定為: \(duckingLevel)")
    }
    
    func setOverlayVolumeBoost(_ boost: Float) {
        overlayVolumeBoost = max(0.0, min(0.5, boost))
        saveSettings()
        print("🔊 [Audio] 疊加音量提升設定為: \(overlayVolumeBoost)")
    }
    
    // MARK: - 核心語音播報邏輯
    
    private func performSpeech(_ message: String, priority: SpeechPriority, category: String) {
        guard isAudioEnabled || priority == .urgent else {
            print("🔇 [Audio] 語音已關閉，跳過播報")
            return
        }
        
        // 檢查重複播報
        if !canAnnounce(message, category: category, priority: priority) {
            return
        }
        
        // 只有緊急播報才忽略中斷狀態
        if isInterrupted && priority != .urgent {
            print("🔇 [Audio] 音頻被中斷，跳過非緊急播報")
            return
        }
        
        // 停止當前播報（如果是更高優先級）
        if priority.rawValue >= SpeechPriority.high.rawValue && speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // 執行播報
        executeSpeech(message, priority: priority, category: category)
    }
    
    // 新增：強制執行語音播報（忽略所有限制）
    private func executeSpeechForced(_ message: String, priority: SpeechPriority, category: String) {
        print("🚨 [Audio] 強制執行語音播報: \(message)")
        
        // 重置中斷狀態
        isInterrupted = false
        
        // 停止當前播報
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        // 強制執行播報
        executeSpeech(message, priority: priority, category: category)
    }
    
    // MARK: - 語音播報方法
    
    private func executeSpeech(_ message: String, priority: SpeechPriority, category: String) {
        // 修正：在播報前才設定音頻會話
        prepareAudioSessionForSpeechOnly()
        
        DispatchQueue.main.async {
            let utterance = AVSpeechUtterance(string: message)
            utterance.voice = AVSpeechSynthesisVoice(language: self._voiceLanguage)
            
            // 根據音頻狀態和優先級動態調整語音參數
            self.configureUtteranceForCurrentState(utterance, priority: priority)
            
            // 記錄播報歷史
            self.updateAnnouncementHistory(message, category: category)
            
            // 執行播報
            self.speechSynthesizer.speak(utterance)
            self.isSpeaking = true
            print("🎤 [Audio] 開始播報: \(message)")
        }
    }
    
    private func configureUtteranceForCurrentState(_ utterance: AVSpeechUtterance, priority: SpeechPriority) {
        let baseRate = _speechRate
        let baseVolume = _speechVolume
        
        let currentEnvironment = analyzeCurrentAudioEnvironment()
        
        switch currentEnvironment {
        case .silent:
            // 無其他音頻：正常設定
            utterance.rate = baseRate
            utterance.volume = baseVolume
            utterance.preUtteranceDelay = 0.2
            
        case .music:
            // 音樂環境：稍微提高音量
            utterance.rate = baseRate
            utterance.volume = min(1.0, baseVolume + 0.1)
            utterance.preUtteranceDelay = 0.3
            
        case .video:
            // 影片環境：明顯提高音量和清晰度
            utterance.rate = max(0.4, baseRate - 0.1)
            utterance.volume = min(1.0, baseVolume + overlayVolumeBoost)
            utterance.preUtteranceDelay = 0.3
            
        case .podcast:
            // 播客環境：正常設定（會被暫停）
            utterance.rate = baseRate
            utterance.volume = baseVolume
            utterance.preUtteranceDelay = 0.1
            
        case .game:
            // 遊戲環境：稍微提高音量
            utterance.rate = baseRate
            utterance.volume = min(1.0, baseVolume + 0.1)
            utterance.preUtteranceDelay = 0.2
        }
        
        // 優先級調整
        if priority == .urgent {
            utterance.volume = min(1.0, utterance.volume + 0.2)
            utterance.rate = max(0.3, utterance.rate - 0.1)
        } else if priority == .high {
            utterance.volume = min(1.0, utterance.volume + 0.1)
        }
        
        print("🎛️ [Audio] 語音參數 - 環境:\(currentEnvironment), 音量:\(utterance.volume), 速度:\(utterance.rate)")
    }
    
    // MARK: - 音頻恢復機制（優化版）
    
    private func restoreAudioState() {
        print("🔄 [Audio] 播報完成，準備恢復音頻狀態")
        
        // 延遲恢復，確保播報完全結束
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            
            // 恢復原始音頻設定
            self.restoreOriginalAudioSession()
            
            // 重置狀態
            self.audioMixState = .normal
            self.currentAudioApp = nil
            
            print("✅ [Audio] 音頻狀態恢復完成")
        }
    }
    
    // MARK: - AVSpeechSynthesizerDelegate 實現（新增音量恢復）
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("✅ [Audio] 語音播報完成")
        isSpeaking = false
        
        // 播報完成後立即恢復音頻狀態
        restoreAudioState()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("❌ [Audio] 語音播報被取消")
        isSpeaking = false
        
        // 取消時也要恢復音頻狀態
        restoreAudioState()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("🎤 [Audio] 語音播報開始")
        isSpeaking = true
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("⏸️ [Audio] 語音播報暫停")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        print("▶️ [Audio] 語音播報繼續")
    }
    
    // MARK: - 重複播報檢查
    
    private func canAnnounce(_ content: String, category: String, priority: SpeechPriority) -> Bool {
        let key = "\(category)_\(content)"
        let now = Date()
        
        // 緊急和測試播報總是允許
        if priority == .urgent {
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
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.isHeadphonesConnected != headphonesConnected {
                self.isHeadphonesConnected = headphonesConnected
                print("🎧 [Audio] 耳機狀態變更: \(headphonesConnected ? "已連接" : "已斷開")")
            }
        }
    }
    
    private func setupSpeechDelegate() {
        speechSynthesizer.delegate = self
    }
    
    private func updateNowPlayingInfo(with status: String = "等車中") {
        var nowPlayingInfo = [String: Any]()
        
        if let destination = currentDestination {
            nowPlayingInfo[MPMediaItemPropertyTitle] = "公車來了"
            nowPlayingInfo[MPMediaItemPropertyArtist] = destination
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = status
        } else {
            nowPlayingInfo[MPMediaItemPropertyTitle] = "公車來了"
            nowPlayingInfo[MPMediaItemPropertyArtist] = "準備搭車"
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = status
        }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isTrackingActive ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    // MARK: - 持久化
    
    private func saveSettings() {
        UserDefaults.standard.set(isAudioEnabled, forKey: "audioEnabled")
        UserDefaults.standard.set(smartVolumeEnabled, forKey: "smartVolumeEnabled")
        UserDefaults.standard.set(videoModeEnabled, forKey: "videoModeEnabled")
        UserDefaults.standard.set(duckingLevel, forKey: "duckingLevel")
        UserDefaults.standard.set(overlayVolumeBoost, forKey: "overlayVolumeBoost")
        UserDefaults.standard.set(notificationDistance, forKey: "notificationDistance")
        UserDefaults.standard.set(_speechRate, forKey: "speechRate")
        UserDefaults.standard.set(_speechVolume, forKey: "speechVolume")
        UserDefaults.standard.set(_voiceLanguage, forKey: "voiceLanguage")
    }
    
    private func loadSettings() {
        isAudioEnabled = UserDefaults.standard.bool(forKey: "audioEnabled")
        if !UserDefaults.standard.objectExists(forKey: "audioEnabled") {
            isAudioEnabled = true
        }
        
        smartVolumeEnabled = UserDefaults.standard.bool(forKey: "smartVolumeEnabled")
        if !UserDefaults.standard.objectExists(forKey: "smartVolumeEnabled") {
            smartVolumeEnabled = true
        }
        
        videoModeEnabled = UserDefaults.standard.bool(forKey: "videoModeEnabled")
        if !UserDefaults.standard.objectExists(forKey: "videoModeEnabled") {
            videoModeEnabled = true
        }
        
        duckingLevel = UserDefaults.standard.float(forKey: "duckingLevel")
        if duckingLevel == 0 { duckingLevel = 0.3 }
        
        overlayVolumeBoost = UserDefaults.standard.float(forKey: "overlayVolumeBoost")
        if overlayVolumeBoost == 0 { overlayVolumeBoost = 0.2 }
        
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
        
        // 重置時也恢復音頻狀態
        if audioSessionConfigured {
            restoreOriginalAudioSession()
        }
        
        print("🔄 [Audio] 已重置音頻通知狀態")
    }
    
    // MARK: - 音頻環境監控（僅監控變化）
    
    func startAudioEnvironmentMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nowPlayingInfoChanged),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateChanged),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: nil
        )
        
        print("🎵 [Audio] 音頻環境監控已啟動（僅監控變化）")
    }
    
    // MARK: - 調試和診斷方法
    
    func getCurrentAudioEnvironmentInfo() -> String {
        let environment = analyzeCurrentAudioEnvironment()
        let audioSession = AVAudioSession.sharedInstance()
        
        var info = "音頻環境: \(environment)\n"
        info += "混合狀態: \(audioMixState)\n"
        info += "其他音頻播放: \(audioSession.isOtherAudioPlaying)\n"
        info += "耳機連接: \(isHeadphonesConnected)\n"
        info += "智慧音量: \(smartVolumeEnabled)\n"
        info += "影片模式: \(videoModeEnabled)\n"
        info += "音頻會話已設定: \(audioSessionConfigured)\n"
        info += "需要恢復音量: \(shouldRestoreVolume)\n"
        
        if let app = currentAudioApp {
            info += "音頻App: \(app)\n"
        }
        
        let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        if let title = nowPlayingInfo?[MPMediaItemPropertyTitle] as? String {
            info += "正在播放: \(title)\n"
        }
        
        return info
    }
    
    func forceAudioEnvironmentRefresh() {
        print("🔄 [Audio] 強制刷新音頻環境（僅更新狀態）")
    }
    
    // MARK: - 音頻環境監控處理（僅記錄變化）
    
    @objc private func audioRouteChanged(notification: Notification) {
        checkHeadphoneConnection()
        print("🎧 [Audio] 音頻路徑變更")
    }
    
    @objc private func nowPlayingInfoChanged() {
        print("🎵 [Audio] 正在播放資訊變更")
    }
    
    @objc private func playbackStateChanged() {
        print("⏯️ [Audio] 播放狀態變更")
    }
    
    // MARK: - 屬性訪問器
    
    var voiceLanguage: String { _voiceLanguage }
    var speechRate: Float { _speechRate }
    var speechVolume: Float { _speechVolume }
    
    // MARK: - 清理方法
    
    deinit {
        stopLocationTracking()
        NotificationCenter.default.removeObserver(self)
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        // 確保恢復音頻設定
        if audioSessionConfigured {
            restoreOriginalAudioSession()
        }
        
        print("🗑️ [Audio] AudioNotificationService 已清理")
    }
}

// MARK: - 語音優先級
private enum SpeechPriority: Int, CaseIterable {
    case normal = 1
    case high = 2
    case urgent = 3
}

// MARK: - UserDefaults 擴展
extension UserDefaults {
    func objectExists(forKey key: String) -> Bool {
        return object(forKey: key) != nil
    }
}
