//
//  RouteSelectionView.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/5/15.
//

import SwiftUI

struct RouteSelectionView: View {
    @StateObject private var tdxService = TDXService.shared
    @State private var selectedCity = City.allCities[0]
    @State private var routes: [BusRoute] = []
    @State private var searchText = ""
    @State private var showingAlert = false
    @State private var isFirstLoad = true
    
    @AppStorage("favoriteRoutes") private var favoriteRoutesData: Data = Data()
    @State private var favoriteRoutes: [BusRoute] = []
    
    var filteredRoutes: [BusRoute] {
        let filtered = searchText.isEmpty ? routes : routes.filter {
            $0.RouteName.Zh_tw.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted { $0.RouteName.Zh_tw.localizedStandardCompare($1.RouteName.Zh_tw) == .orderedAscending }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 城市選擇器
                cityPicker
                
                // 搜尋欄
                searchBar
                
                // 內容區域 - 使用 ZStack 來避免高度跳動
                ZStack {
                    // 背景色
                    Color(.systemGroupedBackground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // 內容視圖
                    contentView
                        .animation(.easeInOut(duration: 0.3), value: tdxService.isLoading)
                        .animation(.easeInOut(duration: 0.3), value: routes.count)
                }
            }
            .navigationTitle("公車路線")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await refreshData()
            }
            .onAppear {
                loadFavoriteRoutes()
                if routes.isEmpty {
                    fetchRoutes()
                }
            }
            .alert("連線錯誤", isPresented: $showingAlert) {
                Button("重試") { fetchRoutes() }
                Button("取消", role: .cancel) { }
            } message: {
                Text(tdxService.errorMessage ?? "未知錯誤")
            }
        }
    }
    

    
    // 城市選擇器
    private var cityPicker: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "location.circle.fill")
                    .foregroundColor(.orange)
                Text("選擇城市")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(City.allCities) { city in
                        Button(action: {
                            selectCity(city)
                        }) {
                            VStack(spacing: 4) {
                                Text(city.nameZh)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(selectedCity.id == city.id ? .white : .primary)
                                
                                // 路線數量顯示，使用動畫
                                Group {
                                    if selectedCity.id == city.id && !routes.isEmpty {
                                        Text("\(routes.count) 條路線")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.8))
                                    } else if selectedCity.id == city.id && tdxService.isLoading {
                                        Text("載入中...")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.8))
                                    } else {
                                        Text(" ")
                                            .font(.caption2)
                                    }
                                }
                                .animation(.easeInOut(duration: 0.3), value: routes.count)
                                .animation(.easeInOut(duration: 0.3), value: tdxService.isLoading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(selectedCity.id == city.id ?
                                          Color.blue : Color(.systemGray6))
                                    .animation(.easeInOut(duration: 0.3), value: selectedCity.id)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
    }
    
    // 搜尋欄
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("搜尋路線 (例: 307, 紅30)", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.2), value: searchText.isEmpty)
    }
    
    // 內容視圖 - 使用過渡動畫
    @ViewBuilder
    private var contentView: some View {
        if tdxService.isLoading && routes.isEmpty {
            loadingView
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else if let errorMessage = tdxService.errorMessage, routes.isEmpty {
            errorView(errorMessage)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if filteredRoutes.isEmpty && !searchText.isEmpty {
            emptySearchView
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else if routes.isEmpty {
            emptyDataView
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            routeList
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }
    
    // 載入視圖
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.5)
            
            VStack(spacing: 8) {
                Text("載入中...")
                    .font(.headline)
                
                Text("正在取得 \(selectedCity.nameZh) 的公車路線")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 錯誤視圖
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("載入失敗")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button("重新載入") {
                fetchRoutes()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 空搜尋結果視圖
    private var emptySearchView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text("找不到相關路線")
                .font(.headline)
            
            Text("試試搜尋其他關鍵字")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 空數據視圖
    private var emptyDataView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bus")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text("暫無路線資料")
                .font(.headline)
            
            Button("重新載入") {
                fetchRoutes()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 路線列表 - 添加淡入動畫
    private var routeList: some View {
        List {
            if !searchText.isEmpty && !filteredRoutes.isEmpty {
                Section {
                    Text("找到 \(filteredRoutes.count) 條相關路線")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            
            ForEach(Array(filteredRoutes.enumerated()), id: \.element.id) { index, route in
                NavigationLink(destination: RouteDetailView(route: route)) {
                    RouteRowView(
                        route: route,
                        isFavorite: favoriteRoutes.contains { $0.RouteID == route.RouteID }
                    ) {
                        toggleFavorite(route)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .padding(.vertical, 2)
                )
                // 交錯動畫效果
                .opacity(tdxService.isLoading ? 0.3 : 1.0)
                .animation(.easeInOut(duration: 0.3).delay(Double(index) * 0.05), value: tdxService.isLoading)
            }
        }
        .listStyle(PlainListStyle())
    }
    
    // 城市選擇方法 - 添加動畫
    private func selectCity(_ city: City) {
        guard selectedCity.id != city.id else { return }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedCity = city
        }
        
        // 延遲一點再獲取數據，讓動畫更流暢
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            fetchRoutes()
        }
    }
    
    // 獲取路線數據 - 添加平滑過渡
    private func fetchRoutes() {
        isFirstLoad = false
        
        // 如果不是第一次載入，不要立即清空列表
        if !routes.isEmpty {
            // 漸變隱藏當前列表
            withAnimation(.easeInOut(duration: 0.2)) {
                // 保持列表，但添加載入狀態
            }
        } else {
            routes = []
        }
        
        tdxService.getAllRoutes(city: selectedCity.id) { fetchedRoutes, error in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    if let routes = fetchedRoutes {
                        self.routes = routes
                    } else if error != nil {
                        self.routes = []
                        self.showingAlert = true
                    }
                }
            }
        }
    }
    
    // 刷新數據
    private func refreshData() async {
        await withCheckedContinuation { continuation in
            fetchRoutes()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                continuation.resume()
            }
        }
    }
    
    // 載入收藏路線
    private func loadFavoriteRoutes() {
        if let decoded = try? JSONDecoder().decode([BusRoute].self, from: favoriteRoutesData) {
            favoriteRoutes = decoded
        }
    }
    
    // 切換收藏狀態
    private func toggleFavorite(_ route: BusRoute) {
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

// 路線行視圖 - 保持不變
struct RouteRowView: View {
    let route: BusRoute
    let isFavorite: Bool
    let onFavoriteToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 路線號碼
            Text(route.RouteName.Zh_tw)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.blue)
                .frame(minWidth: 60, alignment: .leading)
            
            // 路線信息
            VStack(alignment: .leading, spacing: 4) {
                if let departure = route.DepartureStopNameZh,
                   let destination = route.DestinationStopNameZh {
                    HStack {
                        Text(departure)
                            .font(.subheadline)
                            .lineLimit(1)
                        
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(destination)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                } else {
                    Text("路線資訊")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text("點擊查看詳細資訊")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 收藏按鈕
            Button(action: onFavoriteToggle) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .foregroundColor(isFavorite ? .red : .gray)
                    .font(.title3)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}
