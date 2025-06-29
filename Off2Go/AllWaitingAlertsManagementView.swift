//
//  AllWaitingAlertsManagementView.swift
//  Off2Go
//

import SwiftUI

struct AllWaitingAlertsManagementView: View {
    @StateObject private var waitingService = WaitingBusService.shared
    @Environment(\.dismiss) private var dismiss
    
    // 新增：可選的路線過濾
    let filterByRoute: String?
    
    // 初始化器
    init(filterByRoute: String? = nil) {
        self.filterByRoute = filterByRoute
    }
    
    // 根據是否有路線過濾來決定顯示的提醒
    private var displayedAlerts: [WaitingBusAlert] {
        if let routeName = filterByRoute {
            return waitingService.activeAlerts.filter { $0.routeName == routeName }
        } else {
            return waitingService.activeAlerts
        }
    }
    
    // 按路線分組（只在顯示全部時使用）
    private var groupedAlerts: [String: [WaitingBusAlert]] {
        Dictionary(grouping: displayedAlerts) { $0.routeName }
    }
    
    // 標題
    private var navigationTitle: String {
        if filterByRoute != nil {
            return "本路線等車提醒"
        } else {
            return "等車提醒管理"
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                if displayedAlerts.isEmpty {
                    emptyStateView
                } else if filterByRoute != nil {
                    // 單一路線模式：直接顯示列表
                    singleRouteSection
                } else {
                    // 全域模式：按路線分組顯示
                    allRoutesSection
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // 單一路線區段
    private var singleRouteSection: some View {
        Section {
            ForEach(displayedAlerts) { alert in
                WaitingAlertRowView(
                    alert: alert,
                    showRouteName: false,
                    onRemove: {
                        waitingService.removeWaitingAlert(alert)
                    }
                )
            }
        } header: {
            if let routeName = filterByRoute {
                Text("路線 \(routeName)")
            }
        } footer: {
            Text("系統會在公車即將到站前自動通知您")
        }
    }
    
    // 全部路線區段
    private var allRoutesSection: some View {
        Group {
            // 總覽區塊
            Section {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.orange)
                    
                    Text("總共 \(displayedAlerts.count) 個等車提醒")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(groupedAlerts.count) 條路線")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            // 按路線分組顯示
            ForEach(groupedAlerts.keys.sorted(), id: \.self) { routeName in
                Section(header: routeSectionHeader(routeName: routeName)) {
                    ForEach(groupedAlerts[routeName] ?? []) { alert in
                        WaitingAlertRowView(
                            alert: alert,
                            showRouteName: false, // 已經在 Section header 顯示了
                            onRemove: {
                                waitingService.removeWaitingAlert(alert)
                            }
                        )
                    }
                }
            }
            
            // 操作區塊
            Section {
                Button(action: {
                    waitingService.clearAllAlerts()
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                        Text("清除所有等車提醒")
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text("無等車提醒")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text(filterByRoute != nil ? "本路線尚無等車提醒" : "在路線詳情頁面設定等車提醒")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }
    
    private func routeSectionHeader(routeName: String) -> some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "bus.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                Text(routeName)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.blue)
            )
            
            Spacer()
            
            let routeAlerts = groupedAlerts[routeName] ?? []
            Text("\(routeAlerts.count) 個提醒")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct WaitingAlertRowView: View {
    let alert: WaitingBusAlert
    let showRouteName: Bool
    let onRemove: () -> Void
    
    init(alert: WaitingBusAlert, showRouteName: Bool = true, onRemove: @escaping () -> Void) {
        self.alert = alert
        self.showRouteName = showRouteName
        self.onRemove = onRemove
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 提醒圖標
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.2))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "bell.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
            
            // 提醒資訊
            VStack(alignment: .leading, spacing: 4) {
                if showRouteName {
                    Text("\(alert.routeName) - \(alert.stopName)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                } else {
                    Text(alert.stopName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                HStack(spacing: 8) {
                    Text("提前 \(alert.alertMinutes) 分鐘")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text("設定於 \(alert.formattedCreatedTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 移除按鈕
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.title3)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 2)
    }
}
