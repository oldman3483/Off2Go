//
//  LaunchScreen.swift
//  BusNotify
//
//  Created by Heidie Lee on 2025/5/15.
//

import SwiftUI

struct LaunchScreen: View {
    var body: some View {
        VStack {
            Spacer()
            
            Image(systemName: "bus.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .padding()
            
            Text("BusNotify")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("公車站點通知小幫手")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("v1.0.0")
                .font(.caption)
                .padding()
        }
    }
}
