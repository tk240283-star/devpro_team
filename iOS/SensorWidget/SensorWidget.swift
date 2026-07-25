//
//  SensorWidget.swift
//  SensorWidget
//
//  Created by 齊藤 洸希 on 2026/06/14.
//

import WidgetKit
import SwiftUI

struct SensorWidgetEntry: TimelineEntry {
    let date: Date
    let temperature: Double
    let humidity: Double
    let statusText: String
    let statusColor: Color
    let isError: Bool
}

// デコード用の簡易構造体
struct WidgetApiData: Codable {
    let temperature: Double
    let humidity: Double
}

struct SensorWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SensorWidgetEntry {
        SensorWidgetEntry(date: Date(), temperature: 26.4, humidity: 58.0, statusText: "快適", statusColor: .primary, isError: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SensorWidgetEntry) -> ()) {
        let entry = SensorWidgetEntry(date: Date(), temperature: 26.4, humidity: 58.0, statusText: "快適", statusColor: .primary, isError: false)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        Task {
            var entry: SensorWidgetEntry
            
            if let url = URL(string: "http://10.192.139.1:5001/api/data"),
               let (data, _) = try? await URLSession.shared.data(from: url) {
                
                let decoder = JSONDecoder()
                // メインアプリと同じ方法で安全に最後の最新データをパース
                if let fetched = try? decoder.decode([WidgetApiData].self, from: data), let latest = fetched.last {
                    let status = comfortStatus(temp: latest.temperature, hum: latest.humidity)
                    entry = SensorWidgetEntry(date: Date(), temperature: latest.temperature, humidity: latest.humidity, statusText: status.text, statusColor: status.color, isError: false)
                } else {
                    entry = SensorWidgetEntry(date: Date(), temperature: 0, humidity: 0, statusText: "データ解析エラー", statusColor: .secondary, isError: true)
                }
            } else {
                entry = SensorWidgetEntry(date: Date(), temperature: 0, humidity: 0, statusText: "接続エラー", statusColor: .secondary, isError: true)
            }

            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
    
    private func comfortStatus(temp: Double, hum: Double) -> (text: String, color: Color) {
        if temp >= 30.0 { return ("暑い", .orange) }
        if temp >= 27.0 { return ("やや暑い", .orange) }
        if temp < 20.0 { return ("低温", .blue) }
        if hum >= 70.0 { return ("高湿度", .cyan) }
        if hum < 40.0 { return ("乾燥", .blue) }
        return ("快適", .primary)
    }
}

struct SensorWidgetEntryView : View {
    var entry: SensorWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading) {
            if entry.isError {
                Text(entry.statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(entry.temperature, specifier: "%.1f")℃")
                        .font(.system(size: 36, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(entry.statusColor)
                        .minimumScaleFactor(0.8)
                    
                    Text(entry.statusText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(entry.statusColor)
                }
                
                Spacer()
                
                HStack(alignment: .bottom) {
                    Text("\(Int(entry.humidity))%")
                        .font(.title2.monospacedDigit())
                        .foregroundColor(entry.statusColor == .cyan || entry.statusColor == .blue ? entry.statusColor : .primary)
                    
                    Spacer()
                    
                    Text(entry.date.formatted(.dateTime.hour().minute()))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .containerBackground(Color(UIColor.systemBackground), for: .widget)
    }
}

struct SensorWidget: Widget {
    let kind: String = "SensorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SensorWidgetProvider()) { entry in
            SensorWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("温湿度ダッシュボード")
        .description("最新の気温と湿度をホーム画面で確認します。")
        .supportedFamilies([.systemSmall])
    }
}
