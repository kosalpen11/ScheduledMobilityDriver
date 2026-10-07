//
//  NationalIDCropModel.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/7/26.
//

import CoreGraphics

struct NationalIDCropResult {
    let image: CGImage
    let quad: NationalIDQuad
    let confidence: CGFloat
    let aspect: CGFloat
    let decision: String
}
