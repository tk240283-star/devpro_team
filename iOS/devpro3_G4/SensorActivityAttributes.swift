//
//  SensorActivityAttributes.swift
//  devpro3_G4
//
//  Created by 齊藤 洸希 on 2026/06/14.
//

import Foundation
import ActivityKit

public struct SensorActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // ライブアクティビティやDynamic Islandにリアルタイムに送るデータ
        public var temperature: Double
        public var humidity: Double
        public var updateTime: Date
    }

    public init() {}
}
