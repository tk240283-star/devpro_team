//
//  IPSetupView.swift
//  devpro3_G4
//
//  Created by 齊藤 洸希 on 2026/06/17.
//

import SwiftUI
import LocalAuthentication
import AVFoundation

// MARK: - 履歴を保存するためのデータ構造
struct IPHistoryRecord: Codable, Identifiable {
    var id = UUID()
    let ip: String
    let date: Date
}

struct IPSetupView: View {
    @ObservedObject var viewModel: SensorDataViewModel
    @Binding var currentStep: AppStep
    
    @State private var inputIP: String = UserDefaults.standard.string(forKey: "saved_flask_ip") ?? ""
    @State private var ipHistory: [IPHistoryRecord] = []
    @State private var showHistoryScreen = false
    @State private var errorMessage: String? = nil
    @State private var isConnecting = false
    
    @State private var isShowingQRScanner = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景を画面の隅々まで広げ、キーボード裏の白い隙間を撲滅
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    Spacer()
                    
                    // --- 入力セクション（2段構成） ---
                    VStack(spacing: 16) {
                        // 1段目：IP入力エリア
                        HStack(alignment: .center, spacing: 2) {
                            TextField("10.192.138.239", text: $inputIP)
                                .font(.system(size: 32, weight: .regular, design: .rounded))
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                            
                            Text(":5001")
                                .font(.system(size: 24, weight: .regular, design: .rounded))
                                .foregroundColor(.secondary)
                                .padding(.leading, 2)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(20)
                        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
                        
                        Text("—— または ——")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                        
                        // 2段目：QRスキャンボタン
                        Button(action: authenticateForQRScanner) {
                            HStack(spacing: 8) {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.title2)
                                Text("QRをスキャン")
                                    .font(.headline)
                            }
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(20)
                            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // --- 接続ボタン ---
                    Button(action: { connectToServer(ip: inputIP) }) {
                        if isConnecting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("接続")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(Color(UIColor.systemBackground))
                                .frame(maxWidth: 140)
                                .padding(.vertical, 12)
                                .background(inputIP.isEmpty ? Color.gray : Color.primary)
                                .cornerRadius(24)
                        }
                    }
                    .disabled(inputIP.isEmpty || isConnecting)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                    
                    // --- IP履歴ボタン ---
                    Button(action: authenticateUser) {
                        Text("IP履歴")
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("サーバー設定")
            .navigationBarTitleDisplayMode(.inline)
            // QRスキャナー
            .sheet(isPresented: $isShowingQRScanner) {
                QRScannerView(scannedCode: $inputIP)
                    .ignoresSafeArea()
            }
            // 履歴画面へ遷移
            .navigationDestination(isPresented: $showHistoryScreen) {
                IPHistoryListView(history: $ipHistory) { selectedIP in
                    inputIP = selectedIP
                    connectToServer(ip: selectedIP)
                }
            }
            // QR読み取り後の自動接続ロジック
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AutoConnectIP"))) { notification in
                if let ip = notification.object as? String {
                    self.inputIP = ip
                    self.connectToServer(ip: ip)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("InvalidQRCode"))) { _ in
                self.errorMessage = "このQRコードはdevpro3_G4専用形式ではありません"
            }
            .onAppear { loadHistory() }
        }
    }
    
    // --- 履歴・接続管理関数 ---
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "flask_ip_history_v2"),
           let decoded = try? JSONDecoder().decode([IPHistoryRecord].self, from: data) {
            self.ipHistory = decoded
        }
    }
    
    private func saveHistory(ip: String) {
        var current = ipHistory
        current.removeAll { $0.ip == ip }
        current.insert(IPHistoryRecord(ip: ip, date: Date()), at: 0)
        if current.count > 15 { current.removeLast() }
        if let encoded = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(encoded, forKey: "flask_ip_history_v2")
        }
        ipHistory = current
    }
    
    private func authenticateUser() {
        let context = LAContext()
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "履歴を表示します") { success, _ in
                DispatchQueue.main.async { if success { showHistoryScreen = true } }
            }
        } else {
            showHistoryScreen = true
        }
    }
    
    private func authenticateForQRScanner() {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            errorMessage = "Face ID / Touch IDを有効にするとQRスキャンを利用できます"
            return
        }
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "QRスキャナーを起動します") { success, _ in
            DispatchQueue.main.async {
                if success {
                    errorMessage = nil
                    isShowingQRScanner = true
                } else {
                    errorMessage = "Face ID / Touch IDで認証できませんでした"
                }
            }
        }
    }
    
    private func connectToServer(ip: String) {
        guard !ip.isEmpty else { return }
        isConnecting = true
        errorMessage = nil
        UserDefaults.standard.set(ip, forKey: "saved_flask_ip")
        
        Task {
            viewModel.isDataLoaded = false
            await viewModel.startFetching()
            if viewModel.isDataLoaded {
                saveHistory(ip: ip)
                withAnimation(.linear(duration: 0.3)) { currentStep = .mainUI }
            } else {
                errorMessage = "接続失敗: サーバーを確認してください"
            }
            isConnecting = false
        }
    }
}

// MARK: - IP履歴一覧画面
struct IPHistoryListView: View {
    @Binding var history: [IPHistoryRecord]
    var onSelect: (String) -> Void
    
    var body: some View {
        List(history) { record in
            Button(action: { onSelect(record.ip) }) {
                HStack {
                    Text(formatDate(record.date)).font(.body.monospacedDigit())
                    Spacer()
                    Text(record.ip).font(.body.monospacedDigit()).foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("IP履歴")
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd HH:mm"; f.locale = Locale(identifier: "ja_JP")
        return f.string(from: date)
    }
}

// MARK: - QRコードスキャナー
struct QRScannerView: UIViewControllerRepresentable {
    @Binding var scannedCode: String
    @Environment(\.dismiss) var dismiss
    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, ScannerViewControllerDelegate {
        var parent: QRScannerView
        init(_ parent: QRScannerView) { self.parent = parent }
        func didFindCode(_ code: String) {
            parent.dismiss()
            guard let decodedIP = QRCrypto.decryptIP(code) else {
                NotificationCenter.default.post(name: NSNotification.Name("InvalidQRCode"), object: nil)
                return
            }
            parent.scannedCode = decodedIP
            NotificationCenter.default.post(name: NSNotification.Name("AutoConnectIP"), object: decodedIP)
        }
    }
}

protocol ScannerViewControllerDelegate: AnyObject { func didFindCode(_ code: String) }

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: ScannerViewControllerDelegate?
    var captureSession: AVCaptureSession!
    override func viewDidLoad() {
        super.viewDidLoad()
        captureSession = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), captureSession.canAddInput(input) else { return }
        captureSession.addInput(input)
        let output = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
        }
        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        DispatchQueue.global().async { self.captureSession.startRunning() }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let first = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let code = first.stringValue {
            captureSession.stopRunning()
            delegate?.didFindCode(code)
        }
    }
}
