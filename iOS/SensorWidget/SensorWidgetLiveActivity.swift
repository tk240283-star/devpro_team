//
//  SensorWidgetLiveActivity.swift
//  SensorWidget
//
//  Created by 齊藤 洸希 on 2026/06/14.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct SensorWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SensorActivityAttributes.self) { context in
            // MARK: - ロック画面のライブアクティビティ
            let status = comfortStatus(temp: context.state.temperature, hum: context.state.humidity)
            
            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    Text("\(context.state.temperature, specifier: "%.1f")℃")
                        .font(.system(size: 48, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(status.color)
                        .contentTransition(.numericText())
                    
                    Text(status.text)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(status.color)
                }
                
                Text("\(Int(context.state.humidity))%")
                    .font(.title2)
                    .monospacedDigit()
                    .foregroundColor(status.color == .cyan || status.color == .blue ? status.color : .primary)
                    .contentTransition(.numericText())
                
                Text("更新 \(context.state.updateTime.formatted(.dateTime.hour().minute()))")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding()
            .activityBackgroundTint(Color(UIColor.systemBackground).opacity(0.6))
            .activitySystemActionForegroundColor(.primary)
            
        } dynamicIsland: { context in
            // MARK: - Dynamic Island (上部の島)
            let status = comfortStatus(temp: context.state.temperature, hum: context.state.humidity)
            
            return DynamicIsland {
                // 1. Expanded: 長押しして大きく広がったときのデザイン
                DynamicIslandExpandedRegion(.leading) {
                    Text("\(context.state.temperature, specifier: "%.1f")℃")
                        .font(.title2.monospacedDigit())
                        .foregroundColor(status.color)
                        .contentTransition(.numericText())
                        .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.humidity))%")
                        .font(.title2.monospacedDigit())
                        .foregroundColor(status.color == .cyan || status.color == .blue ? status.color : .primary)
                        .contentTransition(.numericText())
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        Text(status.text)
                            .font(.body)
                            .foregroundColor(status.color)
                        Text("更新 \(context.state.updateTime.formatted(.dateTime.hour().minute()))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                }
            } compactLeading: {
                // 2. Compact Leading: 通常時の島の左側 (数値のみ)
                Text("\(Int(context.state.temperature))°")
                    .font(.body.monospacedDigit())
                    .foregroundColor(status.color)
                    .contentTransition(.numericText())
            } compactTrailing: {
                // 3. Compact Trailing: 通常時の島の右側 (数値のみ)
                Text("\(Int(context.state.humidity))%")
                    .font(.body.monospacedDigit())
                    .foregroundColor(status.color == .cyan || status.color == .blue ? status.color : .primary)
                    .contentTransition(.numericText())
            } minimal: {
                // 4. Minimal: 他のアプリが島を使っているときの最小表示
                Text("\(Int(context.state.temperature))°")
                    .foregroundColor(status.color)
                    .contentTransition(.numericText())
            }
        }
    }
    
    // MARK: - Apple純正基準の快適度判定
    private func comfortStatus(temp: Double, hum: Double) -> (text: String, color: Color) {
        if temp >= 30.0 { return ("暑い", .orange) }
        if temp >= 27.0 { return ("やや暑い", .orange) }
        if temp < 20.0 { return ("低温", .blue) }
        if hum >= 70.0 { return ("高湿度", .cyan) }
        if hum < 40.0 { return ("乾燥", .blue) }
        return ("快適", .primary) // 通常時は静かなモノトーン
    }
}
