//
//  SensorData.swift
//  devpro3_G4
//
//  Created by 齊藤 洸希 on 2026/06/05.
//

import Foundation
import SwiftUI
import Combine
import ActivityKit
import WidgetKit

public enum GraphRange: String, CaseIterable, Sendable {
    case day = "日", week = "週", month = "月", sixMonths = "6か月", year = "年"
    public var seconds: Double {
        switch self {
        case .day: return 3600
        case .week: return 86400
        case .month: return 86400
        case .sixMonths: return 604800
        case .year: return 2592000
        }
    }
}

public struct SensorData: Codable, Identifiable, Equatable, @unchecked Sendable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public let temperature: Double
    public let humidity: Double
}

public enum WBGTRiskLevel: String, CaseIterable, Identifiable, Sendable {
    case danger
    case severeWarning
    case warning
    case attention
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .danger: return "危険"
        case .severeWarning: return "厳重警戒"
        case .warning: return "警戒"
        case .attention: return "注意"
        }
    }
    
    public var themeColor: Color {
        switch self {
        case .danger: return .red
        case .severeWarning: return .orange
        case .warning: return .yellow
        case .attention: return .blue
        }
    }
    
    public var color: Color {
        themeColor
    }
}

public enum WBGTCalculator {
    public static func value(temperature: Double, humidity: Double) -> Double {
        let vaporPressure = (humidity / 100.0) * 6.1078 * pow(10.0, (7.5 * temperature) / (temperature + 237.3))
        return 0.73 * temperature + 0.00192 * temperature * vaporPressure + 0.141 * vaporPressure - 0.1
    }
    
    public static func riskLevel(for wbgt: Double) -> WBGTRiskLevel {
        if wbgt >= 31.0 { return .danger }
        if wbgt >= 28.0 { return .severeWarning }
        if wbgt >= 25.0 { return .warning }
        return .attention
    }
}

public extension SensorData {
    var wbgt: Double {
        WBGTCalculator.value(temperature: temperature, humidity: humidity)
    }
    
    var wbgtRiskLevel: WBGTRiskLevel {
        WBGTCalculator.riskLevel(for: wbgt)
    }
}

public struct StatData: Identifiable, Equatable, @unchecked Sendable {
    public let id = UUID()
    public let date: Date
    public let minTemp: Double, maxTemp: Double, avgTemp: Double
    public let minHum: Double, maxHum: Double, avgHum: Double
}

public struct GraphChartPayload: Equatable, @unchecked Sendable {
    public let data: [StatData]
    public let temperatureAverage: Double
    public let humidityAverage: Double
    public let domainStart: Date
    public let domainEnd: Date
    
    public static let empty = GraphChartPayload(data: [], temperatureAverage: 0, humidityAverage: 0, domainStart: Date(), domainEnd: Date())
}

@MainActor
public class SensorDataViewModel: ObservableObject {
    @Published public var allRawData: [SensorData] = []
    @Published public var statsDay: [StatData] = []
    @Published public var statsWeek: [StatData] = []
    @Published public var statsMonth: [StatData] = []
    @Published public var statsSixMonths: [StatData] = []
    @Published public var statsYear: [StatData] = []
    @Published private var chartPayloads: [GraphRange: GraphChartPayload] = [:]
    @Published public var isCalculatingStats: Bool = false
    @Published public var isDataLoaded: Bool = false
    @Published public var showConnectionAlert: Bool = false
    @Published public private(set) var lastTimestamp: Date?
    
    public var latestSensorData: SensorData? {
        allRawData.last
    }
    
    public var latestWBGT: Double? {
        latestSensorData?.wbgt
    }
    
    public var latestWBGTRiskLevel: WBGTRiskLevel {
        latestSensorData?.wbgtRiskLevel ?? .attention
    }
    
    private let initialDataLimit = 1000
    private let maxChartPoints = 900
    private let pollingIntervalNanoseconds: UInt64 = 5_000_000_000
    private let connectionAlertThreshold = 2
    private var consecutiveFailuresCount = 0
    private var currentActivity: Activity<SensorActivityAttributes>?
    private var backgroundStatsTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var isPollingRefreshInFlight = false
    
    public func startFetching() async {
        backgroundStatsTask?.cancel()
        guard let savedIP = UserDefaults.standard.string(forKey: "saved_flask_ip"), !savedIP.isEmpty else { return }
        guard let url = URL(string: "http://\(savedIP):5001/api/data") else { return }
        
        self.isCalculatingStats = true
        self.isDataLoaded = false
        
        do {
            let fetched = try await Self.fetchSensorData(from: url, priority: .userInitiated)
            registerPollingSuccess()
            
            let initialData = Array(fetched.suffix(initialDataLimit))
            let initialResults = await Self.makeStats(from: initialData, maxChartPoints: maxChartPoints, priority: .userInitiated)
            apply(data: initialData, stats: initialResults)
            self.isDataLoaded = true
            
            if let latestData = fetched.last {
                updateLiveActivity(latest: latestData)
            }
            
            WidgetCenter.shared.reloadAllTimelines()
            startPolling()
            
            guard fetched.count > initialData.count else {
                self.isCalculatingStats = false
                return
            }
            
            backgroundStatsTask = Task { [weak self] in
                let fullResults = await Self.makeStats(from: fetched, maxChartPoints: self?.maxChartPoints ?? 900, priority: .background)
                guard !Task.isCancelled else { return }
                self?.apply(data: fetched, stats: fullResults)
                self?.isCalculatingStats = false
                WidgetCenter.shared.reloadAllTimelines()
            }
            
        } catch {
            print("Fetch error: \(error)")
            self.isCalculatingStats = false
            self.isDataLoaded = false
        }
    }
    
    public func connect(fromDeepLink url: URL) async -> Bool {
        guard let ip = QRCrypto.ipAddress(from: url) else { return false }
        UserDefaults.standard.set(ip, forKey: "saved_flask_ip")
        await startFetching()
        return isDataLoaded
    }
    
    public func addManualData(temperature: Double, humidity: Double) async throws {
        guard let url = dataURL() else {
            throw URLError(.badURL)
        }
        
        let row = SensorData(
            timestamp: Date(),
            temperature: temperature,
            humidity: humidity
        )
        
        try await Self.postManualData(row, to: url, priority: .userInitiated)
        registerPollingSuccess()
        showConnectionAlert = false
        await appendLocalData(row)
    }
    
    public func stopPollingAndResetConnectionState() {
        pollingTask?.cancel()
        pollingTask = nil
        backgroundStatsTask?.cancel()
        backgroundStatsTask = nil
        isPollingRefreshInFlight = false
        consecutiveFailuresCount = 0
        showConnectionAlert = false
        isCalculatingStats = false
    }
    
    private func startPolling() {
        pollingTask?.cancel()
        guard dataURL() != nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.pollingIntervalNanoseconds ?? 5_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refreshFromPolling()
            }
        }
    }
    
    private func refreshFromPolling() async {
        guard !isPollingRefreshInFlight, !isCalculatingStats, let url = dataURL() else { return }
        isPollingRefreshInFlight = true
        defer { isPollingRefreshInFlight = false }
        
        do {
            let currentLastTimestamp = lastTimestamp ?? allRawData.last?.timestamp
            let fetched = try await Self.fetchSensorData(from: url, priority: .background)
            registerPollingSuccess()
            
            let newRows = Self.newRows(from: fetched, after: currentLastTimestamp)
            guard !newRows.isEmpty else { return }
            
            allRawData.append(contentsOf: newRows)
            lastTimestamp = allRawData.last?.timestamp
            isDataLoaded = true
            
            let updatedData = allRawData
            isCalculatingStats = true
            let results = await Self.makeStats(from: updatedData, maxChartPoints: maxChartPoints, priority: .background)
            apply(stats: results)
            isCalculatingStats = false
            
            if let latestData = updatedData.last {
                updateLiveActivity(latest: latestData)
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            registerPollingFailure()
            print("Polling fetch error: \(error)")
        }
    }
    
    private func appendLocalData(_ row: SensorData) async {
        if allRawData.contains(where: { $0.timestamp == row.timestamp }) {
            return
        }
        
        allRawData.append(row)
        allRawData.sort { $0.timestamp < $1.timestamp }
        lastTimestamp = allRawData.last?.timestamp
        isDataLoaded = true
        
        let updatedData = allRawData
        isCalculatingStats = true
        let results = await Self.makeStats(from: updatedData, maxChartPoints: maxChartPoints, priority: .userInitiated)
        apply(stats: results)
        isCalculatingStats = false
        
        if let latestData = updatedData.last {
            updateLiveActivity(latest: latestData)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    private func dataURL() -> URL? {
        guard let savedIP = UserDefaults.standard.string(forKey: "saved_flask_ip"), !savedIP.isEmpty else { return nil }
        return URL(string: "http://\(savedIP):5001/api/data")
    }
    
    private func registerPollingSuccess() {
        consecutiveFailuresCount = 0
    }
    
    private func registerPollingFailure() {
        consecutiveFailuresCount += 1
        if consecutiveFailuresCount >= connectionAlertThreshold {
            showConnectionAlert = true
        }
    }
    
    nonisolated private static func newRows(from fetched: [SensorData], after lastTimestamp: Date?) -> [SensorData] {
        guard let lastTimestamp else { return fetched }
        return fetched.filter { $0.timestamp > lastTimestamp }
    }
    
    nonisolated private static func fetchSensorData(from url: URL, priority: TaskPriority) async throws -> [SensorData] {
        try await Task.detached(priority: priority) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 4.5
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                if let date = formatter.date(from: dateString) { return date }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date")
            }
            return try decoder.decode([SensorData].self, from: data).sorted { $0.timestamp < $1.timestamp }
        }.value
    }
    
    nonisolated private static func postManualData(_ row: SensorData, to url: URL, priority: TaskPriority) async throws {
        try await Task.detached(priority: priority) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 4.5
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            
            let payload: [String: Any] = [
                "timestamp": formatter.string(from: row.timestamp),
                "temperature": row.temperature,
                "humidity": row.humidity
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
        }.value
    }
    
    private typealias StatsResult = (
        day: [StatData],
        week: [StatData],
        month: [StatData],
        sixMonths: [StatData],
        year: [StatData],
        chartPayloads: [GraphRange: GraphChartPayload]
    )
    
    nonisolated private static func makeStats(from data: [SensorData], maxChartPoints: Int, priority: TaskPriority) async -> StatsResult {
        let cal = Calendar.current
        return await Task.detached(priority: priority) {
            let day = SensorDataViewModel.aggregate(.day, data, cal)
            let week = SensorDataViewModel.aggregate(.week, data, cal)
            let month = SensorDataViewModel.aggregate(.month, data, cal)
            let sixMonths = SensorDataViewModel.aggregate(.sixMonths, data, cal)
            let year = SensorDataViewModel.aggregate(.year, data, cal)
            let payloads: [GraphRange: GraphChartPayload] = [
                .day: SensorDataViewModel.makeChartPayload(from: day, maxPointCount: maxChartPoints),
                .week: SensorDataViewModel.makeChartPayload(from: week, maxPointCount: maxChartPoints),
                .month: SensorDataViewModel.makeChartPayload(from: month, maxPointCount: maxChartPoints),
                .sixMonths: SensorDataViewModel.makeChartPayload(from: sixMonths, maxPointCount: maxChartPoints),
                .year: SensorDataViewModel.makeChartPayload(from: year, maxPointCount: maxChartPoints)
            ]
            return (day, week, month, sixMonths, year, payloads)
        }.value
    }
    
    private func apply(data: [SensorData], stats: StatsResult) {
        self.allRawData = data
        self.lastTimestamp = data.last?.timestamp
        apply(stats: stats)
    }
    
    private func apply(stats: StatsResult) {
        self.statsDay = stats.day
        self.statsWeek = stats.week
        self.statsMonth = stats.month
        self.statsSixMonths = stats.sixMonths
        self.statsYear = stats.year
        self.chartPayloads = stats.chartPayloads
    }
    
    nonisolated private static func makeChartPayload(from data: [StatData], maxPointCount: Int) -> GraphChartPayload {
        guard let first = data.first, let last = data.last else {
            let now = Date()
            return GraphChartPayload(data: [], temperatureAverage: 0, humidityAverage: 0, domainStart: now, domainEnd: now)
        }
        let temperatureAverage = average(data.map(\.avgTemp))
        let humidityAverage = average(data.map(\.avgHum))
        let sampledData = downsample(data, maxPointCount: maxPointCount)
        return GraphChartPayload(
            data: sampledData,
            temperatureAverage: temperatureAverage,
            humidityAverage: humidityAverage,
            domainStart: first.date,
            domainEnd: last.date
        )
    }
    
    nonisolated private static func downsample(_ data: [StatData], maxPointCount: Int) -> [StatData] {
        guard maxPointCount > 2, data.count > maxPointCount else { return data }
        let step = Double(data.count - 1) / Double(maxPointCount - 1)
        var sampled: [StatData] = []
        sampled.reserveCapacity(maxPointCount)
        var lastIndex = -1
        
        for pointIndex in 0..<maxPointCount {
            let sourceIndex = min(data.count - 1, Int((Double(pointIndex) * step).rounded()))
            if sourceIndex != lastIndex {
                sampled.append(data[sourceIndex])
                lastIndex = sourceIndex
            }
        }
        
        if sampled.last?.date != data.last?.date {
            sampled.append(data[data.count - 1])
        }
        return sampled
    }
    
    nonisolated private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
    
    private func updateLiveActivity(latest: SensorData) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = SensorActivityAttributes.ContentState(temperature: latest.temperature, humidity: latest.humidity, updateTime: latest.timestamp)
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity = currentActivity {
            Task { await activity.update(content) }
        } else {
            do {
                let attributes = SensorActivityAttributes()
                currentActivity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } catch { print("Live Activity Error: \(error.localizedDescription)") }
        }
    }
    
    nonisolated static func aggregate(_ range: GraphRange, _ data: [SensorData], _ cal: Calendar) -> [StatData] {
        let grouped = Dictionary(grouping: data) { item -> Date in
            if range == .day { return cal.date(bySettingHour: cal.component(.hour, from: item.timestamp), minute: 0, second: 0, of: item.timestamp) ?? item.timestamp }
            else if range == .year { let comp = cal.dateComponents([.year, .month], from: item.timestamp); return cal.date(from: comp) ?? item.timestamp }
            else if range == .sixMonths { let comp = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: item.timestamp); return cal.date(from: comp) ?? item.timestamp }
            else { return cal.startOfDay(for: item.timestamp) }
        }
        return grouped.map { date, values in
            let temps = values.map { $0.temperature }; let hums = values.map { $0.humidity }
            return StatData(date: date, minTemp: temps.min() ?? 0, maxTemp: temps.max() ?? 0, avgTemp: temps.isEmpty ? 0 : temps.reduce(0, +) / Double(temps.count), minHum: hums.min() ?? 0, maxHum: hums.max() ?? 0, avgHum: hums.isEmpty ? 0 : hums.reduce(0, +) / Double(hums.count))
        }.sorted { $0.date < $1.date }
    }
    
    public func getStats(for range: GraphRange) -> [StatData] {
        switch range { case .day: return statsDay; case .week: return statsWeek; case .month: return statsMonth; case .sixMonths: return statsSixMonths; case .year: return statsYear }
    }
    
    public func getChartPayload(for range: GraphRange) -> GraphChartPayload {
        chartPayloads[range] ?? .empty
    }
}
