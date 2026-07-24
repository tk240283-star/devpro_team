//
//  SensorWidgetBundle.swift
//  SensorWidget
//
//  Created by 齊藤 洸希 on 2026/06/14.
//

import WidgetKit
import SwiftUI

@main
struct SensorWidgetBundle: WidgetBundle {
    var body: some Widget {
        SensorWidget()
        SensorWidgetControl()
        SensorWidgetLiveActivity()
    }
}
