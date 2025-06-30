//
//  FavoritesView.swift
//  Off2Go
//
//  修復收藏路線顯示問題
//

import SwiftUI

struct FavoritesView: View {
    @AppStorage("favoriteRoutes") private var favoriteRoutesData: Data = Data()
    @State private var favoriteRoutes: [BusRoute] = []
    @State private var showingDeleteAlert = false
    @State private var routeToDelete: BusRoute?
    @State private var searchText = ""
    @State private var isLoading = true
    
    private var filteredFavorites: [BusRoute] {
        if searchText.isEmpty {
            return favoriteRoutes
        } else {
            return favoriteRoutes.filter {
                $0.RouteName.Zh_tw.localizedCaseInsensitiveContains(searchText) ||
                ($0.DepartureStopNameZh?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ($0.DestinationStopNameZh?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !favoriteRoutes.isEmpty {
                    searchBar
                }
                
                Group {
                    if isLoading {
                        loadingView
                    } else if favoriteRoutes.isEmpty {
                        emptyStateView
                    } else if filteredFavorites.isEmpty {
                        emptySearchView
                    } else {
                        favoritesList
                    }
                }
                
                SmartBannerAdView()
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
            .navigationTitle("收藏路線")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !favoriteRoutes.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                }
            }
            .onAppear {
                print("🔄 [Favorites] onAppear 觸發")
                loadFavoritesFromUserDefaults()
            }
            .compatibleOnChange(of: favoriteRoutesData) {
                print("🔄 [Favorites] AppStorage 數據變更，重新載入")
                loadFavoritesFromUserDefaults()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                print("🔄 [Favorites] App 進入前台，重新載入")
                loadFavoritesFromUserDefaults()
            }
            .alert("確認刪除", isPresented: $showingDeleteAlert) {
                Button("刪除", role: .destructive) {
                    if let route = routeToDelete {
                        removeFromFavorites(route)
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                if let route = routeToDelete {
                    Text("確定要移除路線「\(route.RouteName.Zh_tw)」嗎？")
                }
            }
        }
    }
    
    private func loadFavoritesFromUserDefaults() {
        print("🔍 [Favorites] === 從 UserDefaults 載入收藏 ===")
        
        isLoading = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard !favoriteRoutesData.isEmpty else {
                print("❌ [Favorites] favoriteRoutesData 為空")
                self.favoriteRoutes = []
                self.isLoading = false
                return
            }
            
            print("🔍 [Favorites] favoriteRoutesData 有 \(favoriteRoutesData.count) bytes 資料")
            
            do {
                let decoded = try JSONDecoder().decode([BusRoute].self, from: favoriteRoutesData)
                self.favoriteRoutes = decoded.sorted { $0.RouteName.Zh_tw < $1.RouteName.Zh_tw }
                
                print("✅ [Favorites] 成功載入 \(self.favoriteRoutes.count) 條收藏路線:")
                for route in self.favoriteRoutes {
                    print("   - \(route.RouteName.Zh_tw) (ID: \(route.RouteID))")
                }
            } catch {
                print("❌ [Favorites] 解析失敗: \(error.localizedDescription)")
                self.favoriteRoutes = []
            }
            
            self.isLoading = false
        }
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("搜尋收藏的路線", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .red))
                .scaleEffect(1.2)
            
            Text("載入收藏中...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(.red.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "heart.slash")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.red.opacity(0.7))
            }
            
            VStack(spacing: 12) {
                Text("還沒有收藏的路線")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("在路線詳情頁面點擊❤️來收藏常用路線")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            NavigationLink(destination: RouteSelectionView()) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("瀏覽路線")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(.blue)
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    private var emptySearchView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("找不到相關路線")
                    .font(.headline)
                
                Text("在收藏中搜尋「\(searchText)」沒有結果")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("清除搜尋") {
                searchText = ""
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
    
    private var favoritesList: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                    
                    Text("共收藏 \(favoriteRoutes.count) 條路線")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !searchText.isEmpty {
                        Text("顯示 \(filteredFavorites.count) 項")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .listRowBackground(Color.clear)
            }
            
            Section {
                ForEach(filteredFavorites) { route in
                    NavigationLink(destination: RouteDetailView(route: route)) {
                        FavoriteRouteRowView(route: route)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                            .padding(.vertical, 2)
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            routeToDelete = route
                            showingDeleteAlert = true
                        } label: {
                            Label("移除", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: deleteRoutes)
            }
            
            if !favoriteRoutes.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("小提示", systemImage: "lightbulb")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(PlainListStyle())
        .background(Color(.systemGroupedBackground))
    }
    
    private func removeFromFavorites(_ route: BusRoute) {
        withAnimation(.easeInOut) {
            favoriteRoutes.removeAll { $0.RouteID == route.RouteID }
            saveFavoriteRoutes()
        }
    }
    
    private func deleteRoutes(at offsets: IndexSet) {
        withAnimation(.easeInOut) {
            favoriteRoutes.remove(atOffsets: offsets)
            saveFavoriteRoutes()
        }
    }
    
    private func saveFavoriteRoutes() {
        if let encoded = try? JSONEncoder().encode(favoriteRoutes) {
            favoriteRoutesData = encoded
            print("💾 [Favorites] 已保存 \(favoriteRoutes.count) 條收藏路線到 AppStorage")
        }
    }
}

// MARK: - 收藏路線行視圖 (確保在正確位置)
struct FavoriteRouteRowView: View {
    let route: BusRoute
    
    var body: some View {
        HStack(spacing: 12) {
            // 路線圖標
            HStack(spacing: 6) {
                Image(systemName: "bus.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                Text(route.RouteName.Zh_tw)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.blue)
            )
            
            // 路線信息
            VStack(alignment: .leading, spacing: 6) {
                if let departure = route.DepartureStopNameZh,
                   let destination = route.DestinationStopNameZh {
                    HStack(spacing: 4) {
                        Text(departure)
                            .font(.subheadline)
                            .lineLimit(1)
                        
                        Image(systemName: "arrow.right")
                            .font(.caption2)
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
                
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("點擊查看即時資訊")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 收藏圖標
            Image(systemName: "heart.fill")
                .font(.title3)
                .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }
}
