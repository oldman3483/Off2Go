//
//  RouteDetailView.swift
//  BusNotify
//
//  Created by Heidie Lee on 2025/5/15.
//

import SwiftUI
import CoreLocation

struct RouteDetailView: View {
    let route: BusRoute
    @State private var selectedDirection = 0
    @StateObject private var monitoringService = StationMonitoringService()
    @StateObject private var locationService = LocationService.shared
    @State private var showingLocationAlert = false
    @State private var nearestStopIndex: Int?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 路線信息卡片
                routeInfoCard
                
                // 方向選擇
                directionSelector
                
                // 監控狀態卡片
                if monitoringService.isMonitoring {
                    monitoringStatusCard
                }
                
                // 站點列表
                stopsListView
                
                // 監控按鈕
                monitoringButton
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(route.RouteName.Zh_tw)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            monitoringService.setRoute(route, direction: selectedDirection)
            updateNearestStop()
        }
        .onChange(of: selectedDirection) { newDirection in
            monitoringService.setRoute(route, direction: newDirection)
            updateNearestStop()
        }
        .onChange(of: locationService.currentLocation) { _ in
            updateNearestStop()
        }
        .alert("位置權限", isPresented: $showingLocationAlert) {
            Button("前往設定") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("需要位置權限才能監控附近站點，請在設定中開啟位置服務")
        }
    }
    
    // 路線信息卡片
    private var routeInfoCard: some View {
        VStack(spacing: 12) {
            HStack {
                // 路線圖標和號碼
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
                
                // 收藏按鈕
                FavoriteButton(route: route)
            }
            
            // 路線描述
            if let departure = route.DepartureStopNameZh,
               let destination = route.DestinationStopNameZh {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("起點")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(departure)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right.circle")
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("終點")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(destination)
                            .font(.subheadline)
                            .fontWeight(.medium)
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
    
    // 方向選擇器
    private var directionSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.orange)
                Text("選擇方向")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            Picker("方向", selection: $selectedDirection) {
                Text("去程").tag(0)
                Text("回程").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
    }
    
    // 監控狀態卡片
    private var monitoringStatusCard: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "location.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    
                    Text("監控中")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                Text("共 \(monitoringService.stops.count) 個站點")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.green.opacity(0.2)))
                    .foregroundColor(.green)
            }
            
            if let nearestIndex = nearestStopIndex,
               nearestIndex < monitoringService.stops.count {
                let nearestStop = monitoringService.stops[nearestIndex]
                let distance = calculateDistance(to: nearestStop)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近站點")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(nearestStop.StopName.Zh_tw)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("距離")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(distance)) 公尺")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(distance < 100 ? .red : .primary)
                    }
                }
                .padding(.top, 8)
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.green.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.green.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // 站點列表視圖
    private var stopsListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundColor(.purple)
                Text("站點列表")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if !monitoringService.stops.isEmpty {
                    Text("\(monitoringService.stops.count) 站")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.purple.opacity(0.2)))
                        .foregroundColor(.purple)
                }
            }
            
            if monitoringService.stops.isEmpty {
                // 載入中視圖
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .purple))
                        .scaleEffect(1.2)
                    
                    Text("載入站點中...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                // 站點列表
                LazyVStack(spacing: 8) {
                    ForEach(Array(zip(monitoringService.stops.indices, monitoringService.stops)), id: \.0) { index, stop in
                        StopRowView(
                            stop: stop,
                            index: index,
                            arrival: monitoringService.arrivals[stop.StopID],
                            distance: calculateDistance(to: stop),
                            isNearest: nearestStopIndex == index,
                            isMonitoring: monitoringService.isMonitoring
                        )
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
    
    // 監控按鈕
    private var monitoringButton: some View {
        Button(action: toggleMonitoring) {
            HStack(spacing: 12) {
                Image(systemName: monitoringService.isMonitoring ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                
                Text(monitoringService.isMonitoring ? "停止監控" : "開始監控")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(monitoringService.isMonitoring ? .red : .blue)
            )
            .foregroundColor(.white)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(monitoringService.stops.isEmpty)
    }
    
    // 切換監控狀態
    private func toggleMonitoring() {
        if locationService.authorizationStatus != .authorizedAlways &&
           locationService.authorizationStatus != .authorizedWhenInUse {
            showingLocationAlert = true
            return
        }
        
        if monitoringService.isMonitoring {
            monitoringService.stopMonitoring()
        } else {
            monitoringService.startMonitoring()
        }
    }
    
    // 計算到站點的距離
    private func calculateDistance(to stop: BusStop.Stop) -> Double {
        guard let userLocation = locationService.currentLocation else {
            return Double.infinity
        }
        
        let stopLocation = CLLocation(
            latitude: stop.StopPosition.PositionLat,
            longitude: stop.StopPosition.PositionLon
        )
        
        return userLocation.distance(from: stopLocation)
    }
    
    // 更新最近站點
    private func updateNearestStop() {
        guard !monitoringService.stops.isEmpty,
              let userLocation = locationService.currentLocation else {
            nearestStopIndex = nil
            return
        }
        
        var minDistance = Double.infinity
        var minIndex: Int?
        
        for (index, stop) in monitoringService.stops.enumerated() {
            let distance = calculateDistance(to: stop)
            if distance < minDistance {
                minDistance = distance
                minIndex = index
            }
        }
        
        nearestStopIndex = minIndex
    }
}

// 站點行視圖
struct StopRowView: View {
    let stop: BusStop.Stop
    let index: Int
    let arrival: BusArrival?
    let distance: Double
    let isNearest: Bool
    let isMonitoring: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // 站點序號
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(isNearest ? .orange : .gray)
                )
            
            // 站點信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(stop.StopName.Zh_tw)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if isNearest {
                        Image(systemName: "location.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                // 到站信息
                if let arrival = arrival {
                    Text(arrival.arrivalTimeText)
                        .font(.caption)
                        .foregroundColor(arrival.isComingSoon ? .red : .secondary)
                        .fontWeight(arrival.isComingSoon ? .semibold : .regular)
                } else {
                    Text("無到站資訊")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 距離信息
            VStack(alignment: .trailing, spacing: 4) {
                if distance != Double.infinity {
                    Text(formatDistance(distance))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(distance < 100 ? .red : (distance < 300 ? .orange : .secondary))
                } else {
                    Text("--")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isMonitoring && distance < 200 {
                    Text("監控中")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.green.opacity(0.2)))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isNearest ? .orange.opacity(0.1) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isNearest ? .orange.opacity(0.3) : .clear, lineWidth: 1)
                )
        )
    }
    
    private func formatDistance(_ distance: Double) -> String {
        if distance < 1000 {
            return "\(Int(distance)) m"
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
}

// 收藏按鈕組件
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
        if favoriteRoutes.contains(where: { $0.RouteID == route.RouteID }) {
            favoriteRoutes.removeAll { $0.RouteID == route.RouteID }
        } else {
            favoriteRoutes.append(route)
        }
        
        if let encoded = try? JSONEncoder().encode(favoriteRoutes) {
            favoriteRoutesData = encoded
        }
    }
}

#Preview {
    RouteDetailView(
        route: BusRoute(
            RouteID: "12345",
            RouteName: BusRoute.RouteName(Zh_tw: "307", En: "307"),
            DepartureStopNameZh: "台北車站",
            DestinationStopNameZh: "松山車站"
        )
    )
}
