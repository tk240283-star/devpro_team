//
//  ContentView.swift
//  devpro3_G4
//
//  Created by 齊藤 洸希 on 2026/06/05.
//

import SwiftUI

enum AppStep {
    case splash
    case ipSetup
    case mainUI
}

struct ContentView: View {
    @StateObject private var viewModel = SensorDataViewModel()
    @State private var currentStep: AppStep = .splash
    
    var body: some View {
        ZStack {
            switch currentStep {
            case .splash:
                SplashView()
                    .onAppear {
                        // スプラッシュのアニメーション時間を確保してからIP入力画面へ
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation(.easeOut(duration: 0.4)) {
                                currentStep = .ipSetup
                            }
                        }
                    }
                    
            case .ipSetup:
                IPSetupView(viewModel: viewModel, currentStep: $currentStep)
                
            case .mainUI:
                // ▼ ここを修正：元の正しいタブアイコン「thermometer.sun」に戻しました！
                TabView {
                    SummaryTabView(viewModel: viewModel)
                        .tabItem {
                            Label("概要", systemImage: "thermometer.sun")
                        }
                    
                    GraphTabView(viewModel: viewModel)
                        .tabItem {
                            Label("グラフ", systemImage: "chart.xyaxis.line")
                        }
                    
                    HistoryTabView(viewModel: viewModel)
                        .tabItem {
                            Label("履歴", systemImage: "clock.arrow.circlepath")
                        }
                }
                .wbgtNeonBorder(riskLevel: viewModel.latestWBGTRiskLevel)
            }
        }
        .alert("接続が切断されました", isPresented: $viewModel.showConnectionAlert) {
            Button("IP入力画面にもどる") {
                viewModel.stopPollingAndResetConnectionState()
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentStep = .ipSetup
                }
            }
            
            Button("閉じる", role: .cancel) {
                viewModel.showConnectionAlert = false
            }
        } message: {
            Text("Flaskサーバとの接続が切断されました")
        }
    }
}
