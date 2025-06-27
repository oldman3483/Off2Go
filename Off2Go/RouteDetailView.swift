//
//  RouteDetailView.swift - 完整簡化版本
//  Off2Go
//
//  移除監控概念，專注於目的地設定和自動提醒
//

import SwiftUI
import CoreLocation
import Combine

struct RouteDetailView: View {
    let route: BusRoute
    @State private var selectedDirection = 0
    @StateObject private var stationService = StationService() // 重新命名，移除監控概念
    
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var audioService: AudioNotificationService
    
    @State private var selectedDestinationIndex: Int?
    @State private var showingAudioSettings = false
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 路線信息卡片
                routeInfoCard
                
                // 方向選擇卡片
                directionSelectorCard
                
                // 目的地設定狀態卡片
                destinationStatusCard
                
                // 站點列表
                stopsListView
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(route.RouteName.Zh_tw)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        showingAudioSettings = true
                    }) {
                        Label("音頻設定", systemImage: "speaker.wave.2")
                    }
                    
                    if selectedDestinationIndex != nil {
                        Button(action: {
                            clearDestination()
                        }) {
                            Label("清除目的地", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.blue)
                }
            }
        }
        .sheet(isPresented: $showingAudioSettings) {
            AudioSettingsView()
        }
        .onAppear {
            stationService.setRoute(route, direction: selectedDirection)
        }
        .onAppear {
            stationService.setRoute(route, direction: selectedDirection)
            
            // 同步檢查目的地狀態
            syncDestinationState()
        }
        .onChange(of: selectedDirection) { newDirection in
            // 只有當路線已載入且方向真的改變時才處理
            if !stationService.stops.isEmpty {
                print("🔄 [RouteDetail] 方向切換: \(selectedDirection) -> \(newDirection)")
                stationService.setRoute(route, direction: newDirection)
            }
        }
        .onChange(of: locationService.currentLocation) { location in
            // 當位置更新時，檢查是否接近目的地
            if let location = location, selectedDestinationIndex != nil {
                audioService.checkDestinationProximity(currentStops: stationService.stops, userLocation: location)
            }
        }
    }
    
    private func syncDestinationState() {
        // 檢查 AudioService 和 UI 狀態是否同步
        let hasAudioDestination = audioService.currentDestination != nil
        let hasUIDestination = selectedDestinationIndex != nil
        
        print("🔄 [RouteDetail] === 同步目的地狀態 ===")
        print("   Audio 有目的地: \(hasAudioDestination)")
        print("   UI 有目的地: \(hasUIDestination)")
        
        if hasAudioDestination != hasUIDestination {
            print("⚠️ [RouteDetail] 狀態不同步，進行修正")
            
            if hasAudioDestination && !hasUIDestination {
                // Audio 有但 UI 沒有，清除 Audio
                audioService.clearDestination()
            } else if !hasAudioDestination && hasUIDestination {
                // UI 有但 Audio 沒有，清除 UI
                selectedDestinationIndex = nil
            }
        }
    }
    
    // MARK: - 路線信息卡片
    
    private var routeInfoCard: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "bus.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.blue))
                    
                    Text(route.RouteName.Zh_tw)
                        .font(.title)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                FavoriteButton(route: route)
            }
            
            if let departure = route.DepartureStopNameZh,
               let destination = route.DestinationStopNameZh {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("起點")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(selectedDirection == 0 ? departure : destination)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .animation(.easeInOut(duration: 0.3), value: selectedDirection)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right.circle")
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees(selectedDirection == 0 ? 0 : 180))
                        .animation(.easeInOut(duration: 0.3), value: selectedDirection)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("終點")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(selectedDirection == 0 ? destination : departure)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .animation(.easeInOut(duration: 0.3), value: selectedDirection)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
    
    // MARK: - 方向選擇卡片
    
    private var directionSelectorCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "arrow.left.arrow.right.circle")
                    .foregroundColor(.blue)
                    .font(.title3)
                
                Text("選擇行駛方向")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            
            HStack(spacing: 12) {
                DirectionButton(
                    title: "去程",
                    subtitle: route.DestinationStopNameZh ?? "往終點",
                    isSelected: selectedDirection == 0,
                    icon: "arrow.right.circle.fill"
                ) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedDirection = 0
                    }
                }
                
                DirectionButton(
                    title: "回程",
                    subtitle: route.DepartureStopNameZh ?? "往起點",
                    isSelected: selectedDirection == 1,
                    icon: "arrow.left.circle.fill"
                ) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedDirection = 1
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
    }
    
    // MARK: - 目的地狀態卡片
    
    private var destinationStatusCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "bell.circle.fill")
                    .foregroundColor(selectedDestinationIndex != nil ? .green : .gray)
                    .font(.title3)
                
                Text("到站提醒")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if selectedDestinationIndex != nil {
                    // 提醒開關
                    Toggle("", isOn: Binding(
                        get: { audioService.isAudioEnabled },
                        set: { _ in audioService.toggleAudioNotifications() }
                    ))
                    .labelsHidden()
                    .scaleEffect(0.8)
                }
            }
            
            if let destinationIndex = selectedDestinationIndex,
               destinationIndex < stationService.stops.count {
                let destinationStop = stationService.stops[destinationIndex]
                
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        
                        Text("目的地：\(destinationStop.StopName.Zh_tw)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                    }
                    
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        
                        Text("將在接近時自動提醒您")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    
                    // 距離狀態顯示
                    if let userLocation = locationService.currentLocation {
                        let distance = calculateDistance(to: destinationStop, from: userLocation)
                        
                        HStack {
                            Image(systemName: "ruler")
                                .foregroundColor(.blue)
                                .font(.caption)
                            
                            Text("目前距離：\(formatDistance(distance))")
                                .font(.caption)
                                .foregroundColor(distance < 500 ? .orange : .secondary)
                            
                            Spacer()
                        }
                    }
                }
                
            } else {
                HStack {
                    Image(systemName: "hand.point.down.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    
                    Text("點擊下方站點設定目的地，即可自動獲得到站提醒")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(selectedDestinationIndex != nil ? .green.opacity(0.1) : .gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            selectedDestinationIndex != nil ? .green.opacity(0.3) : .gray.opacity(0.3),
                            lineWidth: 1
                        )
                )
        )
    }
    
    // MARK: - 站點列表
    
    private var stopsListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.circle")
                    .foregroundColor(.purple)
                
                Text("站點列表")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if !stationService.stops.isEmpty {
                    Text("\(stationService.stops.count) 站")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.purple.opacity(0.2)))
                        .foregroundColor(.purple)
                }
            }
            
            if let errorMessage = stationService.errorMessage {
                errorView(errorMessage)
            } else if stationService.isLoading {
                loadingView
            } else if stationService.stops.isEmpty {
                emptyStopsView
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(Array(zip(stationService.stops.indices, stationService.stops)), id: \.0) { index, stop in
                        SimpleStopRowView(
                            stop: stop,
                            index: index,
                            isDestination: selectedDestinationIndex == index,
                            arrival: stationService.getArrivalTime(for: stop.StopID),
                            distance: calculateDistanceToStop(stop)
                        ) {
                            // 點擊直接設定為目的地
                            toggleDestination(index: index)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
    }
    
    // MARK: - 目的地設定方法
    
    private func toggleDestination(index: Int) {
        if selectedDestinationIndex == index {
            // 如果是目前目的地，則取消設定
            clearDestination()
        } else {
            // 設定新目的地
            setDestination(index: index)
        }
    }
    
    private func setDestination(index: Int) {
        guard index < stationService.stops.count else { return }
        
        let stop = stationService.stops[index]
        
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedDestinationIndex = index
        }
        
        // 設定音頻服務目的地（自動開始追蹤）
        audioService.setDestination(route.RouteName.Zh_tw, stopName: stop.StopName.Zh_tw)
        
        // 檢查位置權限並開始追蹤
        if !locationService.hasLocationPermission {
            requestLocationPermission()
        } else {
            locationService.startUpdatingLocation()
        }
        
        print("🎯 [RouteDetail] 設定目的地並開始追蹤: \(stop.StopName.Zh_tw)")
    }
    
    private func clearDestination() {
        print("🗑️ [RouteDetail] === 開始清除目的地 ===")
        print("   當前UI狀態 - selectedDestinationIndex: \(selectedDestinationIndex ?? -1)")
        print("   當前Audio狀態 - currentDestination: \(audioService.currentDestination ?? "無")")
        
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedDestinationIndex = nil
        }
        
        // 先檢查 audioService 是否真的有目的地
        if audioService.currentDestination != nil {
            print("🔊 [RouteDetail] AudioService 有目的地，執行清除")
            audioService.clearDestination()
        } else {
            print("ℹ️ [RouteDetail] AudioService 沒有目的地，跳過清除")
        }
        
        locationService.stopUpdatingLocation()
        
        print("✅ [RouteDetail] 目的地清除完成")
    }
    
    private func requestLocationPermission() {
        locationService.requestLocationPermission { success in
            if success {
                DispatchQueue.main.async {
                    self.locationService.startUpdatingLocation()
                }
            } else {
                print("❌ [RouteDetail] 位置權限請求失敗")
                // 可以在這裡顯示權限請求失敗的提示
            }
        }
    }
    
    // MARK: - 距離計算
    
    private func calculateDistance(to stop: BusStop.Stop, from location: CLLocation) -> Double {
        let stopLocation = CLLocation(
            latitude: stop.StopPosition.PositionLat,
            longitude: stop.StopPosition.PositionLon
        )
        return location.distance(from: stopLocation)
    }
    
    private func calculateDistanceToStop(_ stop: BusStop.Stop) -> Double? {
        guard let userLocation = locationService.currentLocation else {
            return nil
        }
        return calculateDistance(to: stop, from: userLocation)
    }
    
    private func formatDistance(_ distance: Double) -> String {
        if distance < 1000 {
            return "\(Int(distance)) 公尺"
        } else {
            return String(format: "%.1f 公里", distance / 1000)
        }
    }
    
    // MARK: - 視圖元件
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundColor(.orange)
            
            Text("載入失敗")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("重新載入") {
                stationService.refreshData()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                .scaleEffect(1.2)
            
            Text("載入站點中...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("路線: \(route.RouteName.Zh_tw)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private var emptyStopsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 30))
                .foregroundColor(.gray)
            
            Text("暫無站點資料")
                .font(.headline)
                .fontWeight(.semibold)
            
            Text("該路線可能暫時沒有站點資訊")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("重新載入") {
                stationService.setRoute(route, direction: selectedDirection)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

// MARK: - 簡化的站點行視圖

struct SimpleStopRowView: View {
    let stop: BusStop.Stop
    let index: Int
    let isDestination: Bool
    let arrival: String?
    let distance: Double?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 站點序號或目的地圖標
                ZStack {
                    Circle()
                        .fill(isDestination ? .green : .blue)
                        .frame(width: 32, height: 32)
                    
                    if isDestination {
                        Image(systemName: "bell.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                    } else {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                
                // 站點資訊
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(stop.StopName.Zh_tw)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if isDestination {
                            Text("目的地")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.green))
                                .foregroundColor(.white)
                        }
                    }
                    
//                    HStack {
//                        // 站牌序號
//                        Text("站牌: \(stop.StopSequence)")
//                            .font(.caption)
//                            .foregroundColor(.secondary)
                        
                        // 到站時間
                        if let arrival = arrival {
                            Text("• \(arrival)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
//                    }
                }
                
                Spacer()
                
                // 距離和動作提示
                VStack(alignment: .trailing, spacing: 4) {
                    // 距離顯示
                    if let distance = distance {
                        Text(formatDistance(distance))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(distanceColor(distance))
                    }
                    
                    // 動作提示
                    Text(isDestination ? "取消提醒" : "設為目的地")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDestination ? .green.opacity(0.1) : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isDestination ? .green.opacity(0.3) : .clear,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatDistance(_ distance: Double) -> String {
        if distance < 1000 {
            return "\(Int(distance))m"
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }
    
    private func distanceColor(_ distance: Double) -> Color {
        if distance < 100 {
            return .red
        } else if distance < 300 {
            return .orange
        } else if distance < 1000 {
            return .blue
        } else {
            return .secondary
        }
    }
}

// MARK: - 支援元件

struct DirectionButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? .blue : .blue.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? .clear : .blue.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 收藏按鈕元件

struct FavoriteButton: View {
    let route: BusRoute
    @AppStorage("favoriteRoutes") private var favoriteRoutesData: Data = Data()
    @State private var favoriteRoutes: [BusRoute] = []
    
    private var isFavorite: Bool {
        favoriteRoutes.contains { $0.RouteID == route.RouteID }
    }
    
    var body: some View {
        Button(action: toggleFavorite) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundColor(isFavorite ? .red : .gray)
        }
        .onAppear {
            loadFavoriteRoutes()
        }
    }
    
    private func loadFavoriteRoutes() {
        if let decoded = try? JSONDecoder().decode([BusRoute].self, from: favoriteRoutesData) {
            favoriteRoutes = decoded
        }
    }
    
    private func toggleFavorite() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if favoriteRoutes.contains(where: { $0.RouteID == route.RouteID }) {
                favoriteRoutes.removeAll { $0.RouteID == route.RouteID }
            } else {
                favoriteRoutes.append(route)
            }
        }
        
        if let encoded = try? JSONEncoder().encode(favoriteRoutes) {
            favoriteRoutesData = encoded
        }
    }
}

#Preview {
    RouteDetailView(route: BusRoute(
        RouteID: "307",
        RouteName: BusRoute.RouteName(Zh_tw: "307", En: "307"),
        DepartureStopNameZh: "撫遠街",
        DestinationStopNameZh: "板橋車站"
    ))
    .environmentObject(LocationService.shared)
    .environmentObject(AudioNotificationService.shared)
}
