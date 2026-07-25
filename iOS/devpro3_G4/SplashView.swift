//
//  SplashView.swift
//  devpro3_G4
//
//  Created by 齊藤 洸希 on 2026/06/14.
//

import SwiftUI

struct SplashView: View {
    // ▼ アニメーションの開始状態を少し調整（0.7倍からスタートして拡大感を強める）
    @State private var logoOpacity = 0.0
    @State private var logoScale = 0.7
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // 背景色（ライト/ダーク）
            (colorScheme == .light ? Color.white : Color.black)
                .ignoresSafeArea()
            
            // Assetsに登録したロゴ
            Image("AppSplashLogo")
                .resizable()
                .scaledToFit()
                // ▼ ここを修正：幅を150から300へ倍増させました。
                // 画面サイズに合わせて自動で高さも調整されます。
                .frame(width: 300)
                // アニメーションの適用
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
        }
        .onAppear {
            // 0.5秒かけて、0.7倍から1.0倍（300px）へ、
            // 違和感のないモーション（easeOut）でふわっと表示
            withAnimation(.easeOut(duration: 0.5)) {
                logoOpacity = 1.0
                logoScale = 1.0 // ここで元のサイズ（300px）になります
            }
        }
    }
}
