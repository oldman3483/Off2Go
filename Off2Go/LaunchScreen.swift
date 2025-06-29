//
//  LaunchScreen.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/5/15.
//

import SwiftUI

struct LaunchScreen: View {
    var body: some View {
        VStack {
            Spacer()
            
            // 可愛的公車圖示
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "bus.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
            }
            .padding()
            
            Text("公車來了")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("Off2Go")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Text("您的貼心搭車小助手")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            
            Spacer()
            
            Text("v1.0.0")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
        }
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.1), .white],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
