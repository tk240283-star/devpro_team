//
//  GraphTabView.swift
//  devpro3_G4
//
//  Created by 齊藤 洸希 on 2026/06/05.
//

import SwiftUI
import Charts

struct GraphTabView: View {
    @ObservedObject var viewModel: SensorDataViewModel
    @State private var selectedRange: GraphRange = .day
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("範囲", selection: $selectedRange) {
                        ForEach(GraphRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    let payload = viewModel.getChartPayload(for: selectedRange)
                    
                    HealthStyleChart(
                        title: "気温", unit: "℃", color: .red,
                        payload: payload, range: selectedRange, isTemperature: true
                    )
                    
                    HealthStyleChart(
                        title: "湿度", unit: "%", color: .blue,
                        payload: payload, range: selectedRange, isTemperature: false
                    )
                }
            }
            .navigationTitle("グラフ")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isCalculatingStats {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
        }
    }
}

struct HealthStyleChart: View {
    let title: String; let unit: String; let color: Color; let payload: GraphChartPayload; let range: GraphRange; let isTemperature: Bool
    
    @State private var selectedDate: Date?
    
    private var data: [StatData] { payload.data }
    private var totalAverage: Double { isTemperature ? payload.temperatureAverage : payload.humidityAverage }
    private var xDomain: ClosedRange<Date> {
        let end = payload.domainEnd > payload.domainStart ? payload.domainEnd : payload.domainStart.addingTimeInterval(1)
        return payload.domainStart...end
    }
    
    // 🌟 劇的軽量化 1：二分探索（Binary Search）による爆速データ検索 🌟
    // 指でなぞった瞬間に、数万件のデータの中からO(log N)の速度で瞬時に該当データをピンポイントで探し出します
    var currentStat: StatData? {
        guard let selectedDate = selectedDate, !data.isEmpty else { return data.last }
        
        var low = 0
        var high = data.count - 1
        
        while low <= high {
            let mid = low + (high - low) / 2
            if data[mid].date == selectedDate { return data[mid] }
            if data[mid].date < selectedDate { low = mid + 1 }
            else { high = mid - 1 }
        }
        
        let c1 = low < data.count ? data[low] : data.last!
        let c2 = high >= 0 ? data[high] : data.first!
        let d1 = abs(c1.date.timeIntervalSince(selectedDate))
        let d2 = abs(c2.date.timeIntervalSince(selectedDate))
        
        return d1 < d2 ? c1 : c2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            if let stat = currentStat {
                VStack(alignment: .leading, spacing: 2) {
                    Text(range == .day ? "日（平均）" : "範囲").font(.caption).foregroundColor(.secondary).bold()
                    
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        if range == .day {
                            Text(String(format: "%.1f", isTemperature ? stat.avgTemp : stat.avgHum))
                                .font(.system(.title, design: .rounded)).bold()
                        } else {
                            let minV = isTemperature ? stat.minTemp : stat.minHum
                            let maxV = isTemperature ? stat.maxTemp : stat.maxHum
                            Text("\(Int(minV))–\(Int(maxV))")
                                .font(.system(.title, design: .rounded)).bold()
                        }
                        
                        Text(unit)
                            .font(.headline).foregroundColor(.secondary)
                        
                        let currentVal = isTemperature ? stat.avgTemp : stat.avgHum
                        let diff = currentVal - totalAverage
                        Text(String(format: diff >= 0 ? "(+%.1f%@)" : "(%.1f%@)", diff, unit))
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.medium)
                            .foregroundColor(diff >= 0 ? .red : .blue)
                    }
                    
                    if range != .day {
                        Text("平均: \(String(format: "%.1f", isTemperature ? stat.avgTemp : stat.avgHum))\(unit)")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    Text(formatHeaderDate(stat.date, for: range)).font(.caption).foregroundColor(.secondary)
                }
                .padding([.horizontal, .top])
            }
            
            Chart {
                RuleMark(y: .value("全体平均", totalAverage))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.6))
                
                ForEach(data) { item in
                    let minV = isTemperature ? item.minTemp : item.minHum
                    let maxV = isTemperature ? item.maxTemp : item.maxHum
                    let avgV = isTemperature ? item.avgTemp : item.avgHum
                    
                    if range == .day {
                        LineMark(x: .value("時間", item.date), y: .value(title, avgV))
                            .foregroundStyle(color)
                            .interpolationMethod(.monotone)
                        
                        AreaMark(x: .value("時間", item.date), y: .value(title, avgV))
                            .foregroundStyle(LinearGradient(colors: [color.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    } else {
                        BarMark(x: .value("期間", item.date), yStart: .value("低", minV), yEnd: .value("高", maxV))
                            .foregroundStyle(color.gradient)
                            .cornerRadius(4)
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartScrollableAxes(.horizontal)
            .chartXScale(domain: xDomain)
            .chartScrollPosition(initialX: data.last?.date ?? Date())
            .chartXVisibleDomain(length: range.seconds * (range == .day ? 24 : range == .week ? 7 : range == .month ? 30 : range == .sixMonths ? 26 : 12))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(formatAxisDate(date, for: range))
                        }
                    }
                }
            }
            .frame(height: 240)
            .padding()
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }
    
    private func formatAxisDate(_ date: Date, for range: GraphRange) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP")
        let comp = Calendar.current.dateComponents([.month, .day, .hour], from: date)
        
        if comp.month == 1 && comp.day == 1 && (comp.hour ?? 0) < 12 {
            return date.formatted(.dateTime.year())
        }
        
        switch range {
        case .day: f.dateFormat = "HH:mm"
        case .week, .month: f.dateFormat = "M/d"
        case .sixMonths: f.dateFormat = "M月"
        case .year: f.dateFormat = "yyyy年"
        }
        return f.string(from: date)
    }
    
    private func formatHeaderDate(_ date: Date, for range: GraphRange) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP")
        switch range {
        case .day: f.dateFormat = "yyyy年M月d日 HH:mm"
        case .week, .month: f.dateFormat = "yyyy年M月d日"
        case .sixMonths: f.dateFormat = "yyyy年M月d日の週"
        case .year: f.dateFormat = "yyyy年M月"
        }
        return f.string(from: date)
    }
}
