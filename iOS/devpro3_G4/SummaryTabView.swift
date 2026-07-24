//
//  SummaryTabView.swift
//  devpro3_G4
//
//  Created by 齊藤 洸希 on 2026/06/12.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import LocalAuthentication

struct SummaryTabView: View {
    @ObservedObject var viewModel: SensorDataViewModel
    
    // QRコード画面を表示するためのフラグ
    @State private var showQRSheet = false
    @State private var qrAuthErrorMessage: String?
    
    // 本日の最高・最低を計算
    private var todayHighLow: (maxT: Double, minT: Double, maxH: Double, minH: Double)? {
        let cal = Calendar.current
        let todayData = viewModel.allRawData.filter { cal.isDateInToday($0.timestamp) }
        guard !todayData.isEmpty else { return nil }
        let temps = todayData.map { $0.temperature }
        let hums = todayData.map { $0.humidity }
        return (temps.max() ?? 0, temps.min() ?? 0, hums.max() ?? 0, hums.min() ?? 0)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    
                    // --- 1. 最新の状況 ---
                    if let latest = viewModel.allRawData.last {
                        Text("最新の状況")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            HStack(spacing: 15) {
                                SummaryCard(title: "気温", value: String(format: "%.1f", latest.temperature), unit: "℃", color: .red, icon: "thermometer.sun")
                                SummaryCard(title: "湿度", value: String(format: "%.0f", latest.humidity), unit: "%", color: .blue, icon: "humidity")
                            }
                            
                            WBGTStatusCard(
                                wbgt: latest.wbgt,
                                riskLevel: latest.wbgtRiskLevel
                            )
                        }
                        .padding(.horizontal)
                    }
                    
                    // --- 2. 本日のハイライト (最高・最低) ---
                    Text("本日のハイライト")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 10)
                    
                    if let hl = todayHighLow {
                        VStack(spacing: 12) {
                            HighlightRow(title: "気温の範囲", minV: hl.minT, maxV: hl.maxT, unit: "℃", color: .red)
                            HighlightRow(title: "湿度の範囲", minV: hl.minH, maxV: hl.maxH, unit: "%", color: .blue)
                        }
                        .padding(.horizontal)
                    } else {
                        Text("本日のデータはまだありません")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                    
                    // --- 3. 環境インサイト ---
                    if let latest = viewModel.allRawData.last {
                        Text("環境インサイト")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 10)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(getInsightMessage(temp: latest.temperature, hum: latest.humidity))
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineSpacing(4)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("概要")
            .background(Color(UIColor.systemGroupedBackground))
            // ナビゲーションバーの右上にボタンを配置
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: authenticateForServerQR) {
                        HStack(spacing: 4) {
                            Image(systemName: "qrcode")
                            Text("サーバーQR")
                        }
                        .font(.body)
                        .fontWeight(.medium)
                    }
                }
            }
            // ボタンを押した時に下からQRコード画面を出す
            .sheet(isPresented: $showQRSheet) {
                ServerQRSheetView()
            }
            .alert("認証が必要です", isPresented: Binding(
                get: { qrAuthErrorMessage != nil },
                set: { if !$0 { qrAuthErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(qrAuthErrorMessage ?? "")
            }
        }
    }
    
    private func authenticateForServerQR() {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            qrAuthErrorMessage = "Face ID / Touch IDを有効にするとサーバーQRを表示できます"
            return
        }
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "サーバーQRを表示します") { success, _ in
            DispatchQueue.main.async {
                if success {
                    qrAuthErrorMessage = nil
                    showQRSheet = true
                } else {
                    qrAuthErrorMessage = "Face ID / Touch IDで認証できませんでした"
                }
            }
        }
    }
    
    private func getInsightMessage(temp: Double, hum: Double) -> String {
        if temp >= 27.0 { return "室温がやや高めになっています。熱中症防止のため、適切なエアコンの使用や水分補給を検討してください。" }
        if temp < 20.0 { return "室温が下がっています。体調管理のため、暖房の調節や暖かい衣服での調整をおすすめします。" }
        if hum < 40.0 { return "空気が乾燥しています。喉や皮膚の乾燥対策として、加湿器の使用を検討してください。" }
        if hum >= 70.0 { return "湿度がかなり高くなっています。カビの発生を抑えるため、換気や除湿を行ってください。" }
        return "現在の温湿度は非常に快適なバランスに保たれています。この状態を維持するのが理想的です。"
    }
}

// MARK: - 既存のカードUIコンポーネント
struct SummaryCard: View {
    let title: String; let value: String; let unit: String; let color: Color; let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon).foregroundColor(color)
                Text(title).font(.subheadline).bold().foregroundColor(color)
            }
            HStack(alignment: .bottom, spacing: 2) {
                Text(value).font(.system(.title, design: .rounded)).bold()
                Text(unit).font(.caption).bold().foregroundColor(.secondary).padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - 既存のハイライトUIコンポーネント
struct HighlightRow: View {
    let title: String; let minV: Double; let maxV: Double; let unit: String; let color: Color
    var body: some View {
        HStack {
            Text(title).font(.body).fontWeight(.medium)
            Spacer()
            Text(String(format: "%.1f", minV)).foregroundColor(.secondary)
            Text("–")
            Text(String(format: "%.1f%@", maxV, unit)).bold().foregroundColor(color)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

struct WBGTStatusCard: View {
    let wbgt: Double
    let riskLevel: WBGTRiskLevel
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sun.max.trianglebadge.exclamationmark")
                .font(.title2)
                .foregroundColor(riskLevel.color)
                .frame(width: 34, height: 34)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("WBGT 暑さ指数")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(riskLevel.color)
                
                HStack(alignment: .bottom, spacing: 4) {
                    Text(String(format: "%.1f", wbgt))
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                    Text("℃")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }
            }
            
            Spacer()
            
            Text(riskLevel.title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(riskLevel.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(riskLevel.color.opacity(0.14))
                .clipShape(Capsule())
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: riskLevel.color.opacity(0.18), radius: 10, x: 0, y: 3)
    }
}

struct WBGTBorderModifier: ViewModifier {
    let riskLevel: WBGTRiskLevel
    let lineWidth: CGFloat = 4
    
    func body(content: Content) -> some View {
        content
            .overlay(
                ContainerRelativeShape()
                    .inset(by: lineWidth / 2)
                    .stroke(
                        LinearGradient(
                            colors: [
                                riskLevel.themeColor,
                                riskLevel.themeColor.opacity(0.3),
                                riskLevel.themeColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: lineWidth
                    )
                    .shadow(color: riskLevel.themeColor.opacity(0.8), radius: 6)
                    .overlay(
                        ContainerRelativeShape()
                            .inset(by: lineWidth / 2)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.65),
                                        riskLevel.themeColor.opacity(0.18),
                                        .white.opacity(0.35)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .allowsHitTesting(false)
                    .ignoresSafeArea(.all)
            )
            .animation(.easeInOut, value: riskLevel)
    }
}

extension View {
    func wbgtNeonBorder(riskLevel: WBGTRiskLevel) -> some View {
        modifier(WBGTBorderModifier(riskLevel: riskLevel))
    }
}

// MARK: - サーバーIPのQRコードを表示するシート画面
struct ServerQRSheetView: View {
    @Environment(\.dismiss) var dismiss
    // UserDefaultsから現在接続中のIPを取得
    @AppStorage("saved_flask_ip") private var savedIP: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if savedIP.isEmpty {
                    Text("IPアドレスが保存されていません")
                        .foregroundColor(.secondary)
                } else {
                    VStack(spacing: 8) {
                        Text("現在のサーバーIP")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(savedIP)
                            .font(.system(.title2, design: .rounded))
                            .bold()
                    }
                    
                    // QRコードの表示
                    Image(uiImage: generateQRCode(from: QRCrypto.deepLinkString(for: savedIP)))
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.08), radius: 15, x: 0, y: 8)
                    
                    Text("このQRコードを他の端末でスキャンすると、\n同じサーバーに素早く接続できます。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        // 文字が「…」と省略されるのを防ぐ
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("サーバーQR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        // ハーフモーダルとして表示（画面の半分、または少し大きめ）
        .presentationDetents([.medium, .fraction(0.6)])
    }
    
    // 文字列をQRコードの画像に変換するメソッド
    private func generateQRCode(from string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        
        if let outputImage = filter.outputImage {
            // QRコードの解像度を上げて鮮明にする
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgimg = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgimg)
            }
        }
        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
}
