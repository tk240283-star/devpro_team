//
//  HistoryTabView.swift
//  devpro3_G4
//
//  Created by 齊藤 洸希 on 2026/06/05.
//

import SwiftUI
import LocalAuthentication
import UIKit
import UniformTypeIdentifiers

struct HistoryTabView: View {
    @ObservedObject var viewModel: SensorDataViewModel
    
    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var isShowingManualInputSheet = false
    @State private var isShowingExportSheet = false
    @State private var exportStartDate = Date()
    @State private var exportEndDate = Date()
    @State private var exportAuthErrorMessage: String?
    @State private var exportErrorMessage: String?
    @State private var shareItem: ExportShareItem?
    
    private var filteredRows: [SensorData] {
        let cal = Calendar.current
        return viewModel.allRawData.filter { item in
            cal.isDate(item.timestamp, inSameDayAs: selectedDate)
        }.sorted { $0.timestamp > $1.timestamp }
    }
    
    var body: some View {
        NavigationStack {
            // ▼ 修正：VStackを廃止し、全体をListで包むことでタイトルの重なりを防止！
            List {
                // --- 1行目：カレンダー選択（背景を透明にして浮かせる） ---
                Section {
                    HStack {
                        Button(action: { showDatePicker.toggle() }) {
                            HStack(spacing: 6) {
                                Text(formatSelectedDate(selectedDate))
                                    .font(.system(.title3, design: .rounded))
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .foregroundColor(.primary)
                                
                                Image(systemName: "chevron.down")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .popover(isPresented: $showDatePicker) {
                            DatePicker(
                                "",
                                selection: $selectedDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                            .environment(\.calendar, Calendar(identifier: .gregorian))
                            .frame(width: 320)
                            .presentationCompactAdaptation(.popover)
                            .padding()
                        }
                        
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear) // セル特有の背景を消して自然に配置
                .listRowInsets(EdgeInsets(top: 10, leading: 4, bottom: 10, trailing: 0))
                .listRowSeparator(.hidden)
                
                // --- 2行目以降：履歴リスト ---
                if filteredRows.isEmpty {
                    VStack {
                        Spacer()
                        Text("この日のデータはありません")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section(header: Text("\(filteredRows.count) 件のデータ (新しい順)")) {
                        ForEach(filteredRows) { row in
                            HStack {
                                Text(row.timestamp.formatted(.dateTime.hour().minute().second()))
                                    .font(.body.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "thermometer.medium").foregroundColor(.red)
                                    Text(String(format: "%.1f℃", row.temperature))
                                        .font(.body.monospacedDigit())
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "drop.fill").foregroundColor(.blue)
                                    Text(String(format: "%.0f%%", row.humidity))
                                        .font(.body.monospacedDigit())
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped) // 純正アプリライクな美しいリスト構造
            .navigationTitle("履歴")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { isShowingManualInputSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("手動データ追加")
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: authenticateForExport) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("エクスポート")
                }
            }
            .sheet(isPresented: $isShowingManualInputSheet) {
                ManualDataInputView { temperature, humidity in
                    try await viewModel.addManualData(temperature: temperature, humidity: humidity)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $isShowingExportSheet) {
                DataExportSheetView(
                    startDate: $exportStartDate,
                    endDate: $exportEndDate,
                    onExport: exportSelectedData
                )
                .presentationDetents([.medium])
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [
                    ExportActivityItemSource(
                        fileURL: item.url,
                        typeIdentifier: item.typeIdentifier
                    )
                ])
            }
            .alert("認証が必要です", isPresented: Binding(
                get: { exportAuthErrorMessage != nil },
                set: { if !$0 { exportAuthErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportAuthErrorMessage ?? "")
            }
            .alert("エクスポートできません", isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage ?? "")
            }
        }
    }
    
    private func formatSelectedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
    
    private func authenticateForExport() {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            exportAuthErrorMessage = "Face ID / Touch IDを有効にすると履歴データをエクスポートできます"
            return
        }
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "履歴データをエクスポートします") { success, _ in
            DispatchQueue.main.async {
                if success {
                    exportAuthErrorMessage = nil
                    prepareExportDates()
                    isShowingExportSheet = true
                } else {
                    exportAuthErrorMessage = "Face ID / Touch IDで認証できませんでした"
                }
            }
        }
    }
    
    private func prepareExportDates() {
        let calendar = Calendar.current
        let startOfSelectedDate = calendar.startOfDay(for: selectedDate)
        exportStartDate = startOfSelectedDate
        
        if calendar.isDateInToday(selectedDate) {
            exportEndDate = Date()
        } else {
            exportEndDate = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfSelectedDate) ?? selectedDate
        }
    }
    
    private func exportSelectedData() {
        guard exportStartDate <= exportEndDate else {
            exportErrorMessage = "終了時刻は開始時刻より後に設定してください"
            return
        }
        
        let exportRows = viewModel.allRawData
            .filter { exportStartDate <= $0.timestamp && $0.timestamp <= exportEndDate }
            .sorted { $0.timestamp < $1.timestamp }
        
        guard !exportRows.isEmpty else {
            exportErrorMessage = "選択した期間にエクスポートできるデータがありません"
            return
        }
        
        do {
            let url = try makeCSVFile(rows: exportRows)
            isShowingExportSheet = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                shareItem = ExportShareItem(url: url, typeIdentifier: UTType.commaSeparatedText.identifier)
            }
        } catch {
            exportErrorMessage = "ファイルの作成に失敗しました"
        }
    }
    
    private func makeCSVFile(rows: [SensorData]) throws -> URL {
        let fileName = "sensor_data_\(fileDateFormatter.string(from: exportStartDate))_\(fileDateFormatter.string(from: exportEndDate)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let text = makeCSV(rows: rows)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    private func makeCSV(rows: [SensorData]) -> String {
        var lines = ["timestamp,temperature,humidity"]
        lines += rows.map { row in
            [
                csvEscaped(exportDateFormatter.string(from: row.timestamp)),
                String(format: "%.2f", row.temperature),
                String(format: "%.2f", row.humidity)
            ].joined(separator: ",")
        }
        return lines.joined(separator: "\n")
    }
    
    private func csvEscaped(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    
    private var exportDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
    
    private var fileDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }
}

private struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
    let typeIdentifier: String
}

private struct ManualDataInputView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var temperatureText = ""
    @State private var humidityText = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    
    let onAdd: (Double, Double) async throws -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("手動データ追加")
                    .font(.headline)
                    .padding(.top, 18)
                
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("温度")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        TextField("25.5", text: $temperatureText)
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(.body.monospacedDigit())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(UIColor.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("湿度")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        TextField("50.0", text: $humidityText)
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(.body.monospacedDigit())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(UIColor.tertiarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(14)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
                
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }
                
                HStack(spacing: 12) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                    Button {
                        Task {
                            await addManualData()
                        }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        } else {
                            Text("追加")
                                .font(.body)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                    .disabled(isSubmitting)
                    .background(Color.accentColor.opacity(isSubmitting ? 0.45 : 1.0))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemGroupedBackground))
        }
    }
    
    private func addManualData() async {
        errorMessage = nil
        
        let temperatureInput = temperatureText.trimmingCharacters(in: .whitespacesAndNewlines)
        let humidityInput = humidityText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !temperatureInput.isEmpty, !humidityInput.isEmpty else {
            errorMessage = "温度と湿度を入力してください"
            return
        }
        
        guard let temperature = Double(temperatureInput.replacingOccurrences(of: ",", with: ".")),
              let humidity = Double(humidityInput.replacingOccurrences(of: ",", with: ".")) else {
            errorMessage = "数値を入力してください"
            return
        }
        
        guard (0.0...100.0).contains(humidity) else {
            errorMessage = "湿度は0〜100の範囲で入力してください"
            return
        }
        
        isSubmitting = true
        do {
            try await onAdd(temperature, humidity)
            isSubmitting = false
            dismiss()
        } catch {
            isSubmitting = false
            errorMessage = "データを追加できませんでした"
        }
    }
}

private struct DataExportSheetView: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    
    let onExport: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Text("エクスポート期間を選択")
                .font(.headline)
                .padding(.top, 14)
            
            VStack(spacing: 0) {
                DatePicker("開始時刻", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .padding(.vertical, 7)
                
                Divider()
                
                DatePicker("終了時刻", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .padding(.vertical, 7)
            }
            .padding(.horizontal, 14)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            
            Text("ご注意：データがある期間のみエクスポートできます。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            
            Button(action: onExport) {
                Text("エクスポート")
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private final class ExportActivityItemSource: NSObject, UIActivityItemSource {
    private let fileURL: URL
    private let typeIdentifier: String
    
    init(fileURL: URL, typeIdentifier: String) {
        self.fileURL = fileURL
        self.typeIdentifier = typeIdentifier
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        fileURL
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        fileURL
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        typeIdentifier
    }
}
