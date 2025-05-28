//
//  DestinationPickerView.swift
//  Off2Go
//
//  Created by Heidie Lee on 2025/5/28.
//

import SwiftUI

struct DestinationPickerView: View {
    let stops: [BusStop.Stop]
    @Binding var selectedStopName: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var audioService: AudioNotificationService
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                        Button(action: {
                            selectedStopName = stop.StopName.Zh_tw
                            audioService.setDestination("", stopName: stop.StopName.Zh_tw)
                            dismiss()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(index + 1). \(stop.StopName.Zh_tw)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    
                                    Text("站牌號碼: \(stop.StopSequence)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if selectedStopName == stop.StopName.Zh_tw {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } header: {
                    Text("選擇目的地站點")
                } footer: {
                    Text("選擇您要下車的站點，我們會在接近時提醒您")
                }
                
                if !selectedStopName.isEmpty {
                    Section {
                        Button("清除目的地") {
                            selectedStopName = ""
                            audioService.clearDestination()
                            dismiss()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("選擇目的地")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    DestinationPickerView(
        stops: [],
        selectedStopName: .constant("")
    )
    .environmentObject(AudioNotificationService.shared)
}
