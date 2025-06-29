//
//  FavoritesView.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/5/15.
//

import SwiftUI

struct FavoritesView: View {
    @AppStorage("favoriteRoutes") private var favoriteRoutesData: Data = Data()
    @State private var favoriteRoutes: [BusRoute] = []
    @State private var showingDeleteAlert = false
    @State private var routeToDelete: BusRoute?
    @State private var searchText = ""
    
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
                    // 搜尋欄
                    searchBar
                }
                
                // 內容區域
                Group {
                    if favoriteRoutes.isEmpty {
                        emptyStateView
                    } else if filteredFavorites.isEmpty {
                        emptySearchView
                    } else {
                        favoritesList
                    }
                }
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
                loadFavoriteRoutes()
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
    
    // 搜尋欄
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
    
    // 空狀態視圖
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 圖標動畫
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
            
            // 快速行動按鈕
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
    
    // 空搜尋結果視圖
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
    
    // 收藏列表
    private var favoritesList: some View {
        List {
            // 統計信息
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
            
            // 路線列表
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
            
            // 提示信息
            if !favoriteRoutes.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("小提示", systemImage: "lightbulb")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                        
                        Text("• 向左滑動可以快速移除收藏\n• 點擊路線可查看詳細資訊並開始監控")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(PlainListStyle())
        .background(Color(.systemGroupedBackground))
    }
    
    // 載入收藏路線
    private func loadFavoriteRoutes() {
        if let decoded = try? JSONDecoder().decode([BusRoute].self, from: favoriteRoutesData) {
            favoriteRoutes = decoded.sorted { $0.RouteName.Zh_tw < $1.RouteName.Zh_tw }
        }
    }
    
    // 從收藏中移除路線
    private func removeFromFavorites(_ route: BusRoute) {
        withAnimation(.easeInOut) {
            favoriteRoutes.removeAll { $0.RouteID == route.RouteID }
            saveFavoriteRoutes()
        }
    }
    
    // 刪除路線（支持編輯模式）
    private func deleteRoutes(at offsets: IndexSet) {
        withAnimation(.easeInOut) {
            favoriteRoutes.remove(atOffsets: offsets)
            saveFavoriteRoutes()
        }
    }
    
    // 保存收藏路線
    private func saveFavoriteRoutes() {
        if let encoded = try? JSONEncoder().encode(favoriteRoutes) {
            favoriteRoutesData = encoded
        }
    }
}

// 收藏路線行視圖
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

