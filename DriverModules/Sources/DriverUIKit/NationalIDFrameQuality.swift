//
//  NationalIDFrameQuality.swift
//  ScheduledMobilityDriver
//

import CoreGraphics
import Foundation

struct NationalIDFrameQuality: Equatable {
    let meanLuma: CGFloat
    let sharpness: CGFloat
    let weakestSharpness: CGFloat
    let tooDark: Bool
    let tooBright: Bool
    let glare: Bool
    let blurry: Bool

    var acceptable: Bool {
        !tooDark && !tooBright && !glare && !blurry
    }

    static let empty = NationalIDFrameQuality(
        meanLuma: 0,
        sharpness: 0,
        weakestSharpness: 0,
        tooDark: false,
        tooBright: false,
        glare: false,
        blurry: true
    )
}

enum NationalIDFrameQualityAssessor {
    static let minimumSharpness: CGFloat = NIDTrackingConfig.blurrySharpness

    static func assess(
        pixels: [UInt8],
        width: Int = NIDTrackingConfig.sampleWidth,
        height: Int = NIDTrackingConfig.sampleHeight,
        minimumSharpness: CGFloat = minimumSharpness,
        maximumMeanLuma: CGFloat = 235,
        clippingLuma: UInt8 = 248
    ) -> NationalIDFrameQuality {
        guard pixels.count == width * height, width > 2, height > 2 else {
            return .empty
        }

        var lumaTotal: CGFloat = 0
        var clipped = 0
        for pixel in pixels {
            lumaTotal += CGFloat(pixel)
            if pixel >= clippingLuma { clipped += 1 }
        }
        let mean = lumaTotal / CGFloat(pixels.count)
        let sharpness = laplacianSharpness(pixels: pixels, width: width, height: height, rect: nil)
        var weakest = CGFloat.greatestFiniteMagnitude
        let patchColumns = 4
        let patchRows = 3
        for row in 0..<patchRows {
            for column in 0..<patchColumns {
                let rect = CGRect(
                    x: CGFloat(column) / CGFloat(patchColumns),
                    y: CGFloat(row) / CGFloat(patchRows),
                    width: 1 / CGFloat(patchColumns),
                    height: 1 / CGFloat(patchRows)
                )
                weakest = min(weakest, laplacianSharpness(pixels: pixels, width: width, height: height, rect: rect))
            }
        }
        if !weakest.isFinite { weakest = 0 }

        return NationalIDFrameQuality(
            meanLuma: mean,
            sharpness: sharpness,
            weakestSharpness: weakest,
            tooDark: mean < 35,
            tooBright: mean > maximumMeanLuma,
            glare: CGFloat(clipped) / CGFloat(pixels.count) > 0.025,
            blurry: sharpness < minimumSharpness
        )
    }

    private static func laplacianSharpness(pixels: [UInt8], width: Int, height: Int, rect: CGRect?) -> CGFloat {
        let minX = max(1, Int((rect?.minX ?? 0) * CGFloat(width)))
        let maxX = min(width - 1, Int((rect?.maxX ?? 1) * CGFloat(width)))
        let minY = max(1, Int((rect?.minY ?? 0) * CGFloat(height)))
        let maxY = min(height - 1, Int((rect?.maxY ?? 1) * CGFloat(height)))
        guard maxX > minX, maxY > minY else { return 0 }

        var energy: CGFloat = 0
        var count: CGFloat = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                let center = CGFloat(pixels[y * width + x])
                let laplacian = CGFloat(pixels[(y - 1) * width + x])
                    + CGFloat(pixels[(y + 1) * width + x])
                    + CGFloat(pixels[y * width + x - 1])
                    + CGFloat(pixels[y * width + x + 1])
                    - 4 * center
                energy += laplacian * laplacian
                count += 1
            }
        }
        return count > 0 ? energy / count : 0
    }
}
