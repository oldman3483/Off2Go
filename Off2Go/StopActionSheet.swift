//
//  StopActionSheet.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/6/27.
//

import SwiftUI

enum StopAction {
    case setAsDestination
    case clearDestination
    case viewOtherRoutes
    case cancel
}

struct StopActionSheet: View {
    let stop: BusStop.Stop
    let index: Int
    let route: BusRoute
    let isCurrentDestination: Bool
    let onAction: (StopAction) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 站點資訊標題
                stopInfoHeader
                
                Divider()
                
                // 動作選項
                actionButtons
                
                Spacer()
            }
            .navigationTitle("站點選項")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("取消") {
                        onAction(.cancel)
                    }
                }
            }
        }
    }
    
    private var stopInfoHeader: some View {
        VStack(spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(.blue)
                        .frame(width: 40, height: 40)
                    
                    if isCurrentDestination {
                        Image(systemName: "flag.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    } else {
                        Text("\(index + 1)")
                            .foregroundColor(.white)
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(stop.StopName.Zh_tw)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("路線: \(route.RouteName.Zh_tw)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(Color(.systemGray6))
    }
    
    private var actionButtons: some View {
        VStack(spacing: 0) {
            if isCurrentDestination {
                ActionButton(
                    icon: "trash",
                    title: "取消目的地設定",
                    subtitle: "移除此站點的到站提醒",
                    color: .red
                ) {
                    onAction(.clearDestination)
                }
            } else {
                ActionButton(
                    icon: "flag.fill",
                    title: "設為目的地",
                    subtitle: "接近此站點時會提醒您下車",
                    color: .green
                ) {
                    onAction(.setAsDestination)
                }
            }
            
            Divider()
                .padding(.horizontal, 20)
            
            ActionButton(
                icon: "bus.fill",
                title: "查看其他路線",
                subtitle: "顯示經過此站牌的其他公車路線",
                color: .blue
            ) {
                onAction(.viewOtherRoutes)
            }
        }
    }
}

struct ActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
