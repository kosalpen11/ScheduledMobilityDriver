//
//  NationalIDVisionProcessor.swift
//  ScheduledMobilityDriver
//
//  Created by Kosal Pen on 10/5/26.
//

import CoreImage
import UIKit
import Vision

struct NationalIDVisionResult {
    let imageData: Data
    let previewImage: UIImage
    let filename: String
    let expiryDate: Date?
    let message: String?
}

enum NationalIDVisionFailure: Error, Equatable {
    case notDetected
    case blurry
    case glare
    case expired
    case unreadable
    case renderFailed

    var message: String {
        switch self {
        case .notDetected:
            return "We could not find a National ID card in this photo. Place the card inside the frame and try again."
        case .blurry:
            return "The National ID photo is too blurry. Retake it with steady hands and good light."
        case .glare:
            return "There is too much glare on the National ID. Tilt the card slightly and try again."
        case .expired:
            return "This National ID appears to be expired. Upload a current document."
        case .unreadable:
            return "We could not read the National ID details. You can try a clearer photo or choose a file."
        case .renderFailed:
            return "The selected National ID photo could not be processed."
        }
    }
}

enum NationalIDVisionProcessor {
    private static let ciContext = CIContext(options: nil)

    static func process(
        image: UIImage,
        fallbackFilename: String,
        expectedStillQuad: NationalIDQuad? = nil
    ) throws -> NationalIDVisionResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        defer {
            debugLog("durationMs=\(Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000))")
        }
        let imageOrientation = image.imageOrientation
        guard let cgImage = image.normalizedUp().cgImage else {
            debugLog("input render failed")
            throw NationalIDVisionFailure.renderFailed
        }
        debugLog("input size=\(cgImage.width)x\(cgImage.height)")
        let processorExpectedQuad = expectedStillQuad.map {
            NationalIDCropper.processorQuad($0, from: imageOrientation)
        }
        if let processorExpectedQuad {
            let tl = format(processorExpectedQuad.topLeft)
            let tr = format(processorExpectedQuad.topRight)
            let br = format(processorExpectedQuad.bottomRight)
            let bl = format(processorExpectedQuad.bottomLeft)
            debugLog("expectedProcessorQuad tl=\(tl) tr=\(tr) br=\(br) bl=\(bl)")
        }
        guard let crop = NationalIDCropper.cropCard(
            in: cgImage,
            expectedQuad: processorExpectedQuad,
            log: debugLog
        ) else {
            debugLog("rectangle not detected")
            throw NationalIDVisionFailure.notDetected
        }
        debugLog("rectangle confidence=\(format(crop.confidence)) aspect=\(format(crop.aspect))")
        let corrected = crop.image
        debugLog("corrected size=\(corrected.width)x\(corrected.height)")

        let qualityImage = downsampleToShortSide(corrected, maxShort: 1013) ?? corrected
        let sharpness = sobelSharpness(qualityImage)
        debugLog("quality sharpness=\(format(CGFloat(sharpness))) scale=sobelRMS")
        guard sharpness >= 0.085 else {
            throw NationalIDVisionFailure.blurry
        }
        let glare = glareScore(corrected)
        debugLog("quality glareScore=\(format(CGFloat(glare)))")
        guard glare >= 0.55 else {
            throw NationalIDVisionFailure.glare
        }

        guard let enhanced = enhance(corrected) else {
            debugLog("enhance failed")
            throw NationalIDVisionFailure.renderFailed
        }
        let ocrResult = recognizeMRZ(in: enhanced)
        if let expiry = ocrResult.expiryDate, isExpired(expiry) {
            debugLog("mrz found=true expiryDetected=true expiry=\(formatDate(expiry)) expired=true")
            throw NationalIDVisionFailure.expired
        }
        let uploadImage = UIImage(cgImage: enhanced)
        guard let data = uploadImage.jpegData(compressionQuality: 0.88) else {
            debugLog("jpeg render failed")
            throw NationalIDVisionFailure.renderFailed
        }
        debugLog("mrz found=\(ocrResult.foundMRZ) expiryDetected=\(ocrResult.expiryDate != nil) expiry=\(ocrResult.expiryDate.map(formatDate) ?? "nil") uploadBytes=\(data.count)")
        let message: String?
        if ocrResult.expiryDate != nil {
            message = "National ID detected. Expiry date was read from the MRZ."
        } else if ocrResult.foundMRZ {
            message = "National ID detected, but expiry date could not be read clearly. Check the expiry before uploading."
        } else {
            message = "National ID detected. Check the expiry before uploading."
        }
        return NationalIDVisionResult(
            imageData: data,
            previewImage: uploadImage,
            filename: fallbackFilename.hasSuffix(".jpg") ? fallbackFilename : "national-id-photo.jpg",
            expiryDate: ocrResult.expiryDate,
            message: message
        )
    }

    private static func downsampleToShortSide(_ image: CGImage, maxShort: Int) -> CGImage? {
        let short = min(image.width, image.height)
        guard short > maxShort else { return image }
        let scale = CGFloat(maxShort) / CGFloat(short)
        let newSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let uiImage = UIImage(cgImage: image)
        let rendered = renderer.image { _ in
            uiImage.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return rendered.cgImage
    }

    private static func sobelSharpness(_ image: CGImage) -> Float {
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data)
        else { return 0 }
        let width = image.width
        let height = image.height
        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        let bytesPerRow = image.bytesPerRow
        guard width > 2, height > 2 else { return 0 }

        var energy: Double = 0
        var samples = 0
        for y in stride(from: 1, to: height - 1, by: 2) {
            for x in stride(from: 1, to: width - 1, by: 2) {
                func luminance(_ px: Int, _ py: Int) -> Double {
                    let offset = py * bytesPerRow + px * bytesPerPixel
                    guard offset + 2 < CFDataGetLength(data) else { return 0 }
                    let r = Double(bytes[offset])
                    let g = Double(bytes[offset + min(1, bytesPerPixel - 1)])
                    let b = Double(bytes[offset + min(2, bytesPerPixel - 1)])
                    return (0.299 * r + 0.587 * g + 0.114 * b) / 255
                }
                let gx = -luminance(x - 1, y - 1) + luminance(x + 1, y - 1)
                    - 2 * luminance(x - 1, y) + 2 * luminance(x + 1, y)
                    - luminance(x - 1, y + 1) + luminance(x + 1, y + 1)
                let gy = luminance(x - 1, y - 1) + 2 * luminance(x, y - 1) + luminance(x + 1, y - 1)
                    - luminance(x - 1, y + 1) - 2 * luminance(x, y + 1) - luminance(x + 1, y + 1)
                energy += gx * gx + gy * gy
                samples += 1
            }
        }
        guard samples > 0 else { return 0 }
        return Float(min(1, sqrt(energy / Double(samples))))
    }

    private static func glareScore(_ image: CGImage) -> Float {
        let side = 256
        var pixels = [UInt8](repeating: 0, count: side * side)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard rendered else { return 0 }
        let clippedRatio = Float(pixels.filter { $0 >= 250 }.count) / Float(pixels.count)
        debugLog("highlights clippedFraction=\(format(CGFloat(clippedRatio)))")
        return max(0, min(1, 1 - clippedRatio * 6))
    }

    private static func enhance(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let shadow = CIFilter(name: "CIHighlightShadowAdjust")
        shadow?.setValue(input, forKey: kCIInputImageKey)
        shadow?.setValue(0.75, forKey: "inputHighlightAmount")
        shadow?.setValue(0.35, forKey: "inputShadowAmount")

        let controls = CIFilter(name: "CIColorControls")
        controls?.setValue(shadow?.outputImage ?? input, forKey: kCIInputImageKey)
        controls?.setValue(1.12, forKey: kCIInputContrastKey)

        guard let output = controls?.outputImage else { return nil }
        return ciContext.createCGImage(output, from: output.extent)
    }

    private static func recognizeMRZ(in image: CGImage) -> MRZOCRResult {
        let orientations: [CGImagePropertyOrientation] = [.up, .down]
        var foundMRZ = false

        for orientation in orientations {
            let result = recognizeMRZ(in: image, orientation: orientation, level: .fast)
            if let expiry = result.expiryDate {
                return MRZOCRResult(foundMRZ: true, expiryDate: expiry)
            }
            foundMRZ = foundMRZ || result.foundMRZ
        }

        for orientation in orientations {
            let result = recognizeMRZ(in: image, orientation: orientation, level: .accurate)
            if let expiry = result.expiryDate {
                return MRZOCRResult(foundMRZ: true, expiryDate: expiry)
            }
            foundMRZ = foundMRZ || result.foundMRZ
        }

        return MRZOCRResult(foundMRZ: foundMRZ, expiryDate: nil)
    }

    private static func recognizeMRZ(
        in image: CGImage,
        orientation: CGImagePropertyOrientation,
        level: VNRequestTextRecognitionLevel
    ) -> MRZOCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.012
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        try? handler.perform([request])
        let lines = (request.results ?? [])
            .flatMap { $0.topCandidates(3).map(\.string) }
            .map(normalizeMRZLine)
            .filter { $0.isEmpty == false }
        let foundMRZ = lines.contains { line in
            line.contains("IDKHM") || line.contains("I<KHM") || line.contains("KHM") || line.contains("<<")
        }
        let expiry = extractExpiryDate(from: lines)
        #if DEBUG
        debugLog(
            "mrz zone=full " +
            "orientation=\(orientation.rawValue) " +
            "level=\(level == .fast ? "fast" : "accurate") " +
            "found=\(foundMRZ) " +
            "expiry=\(expiry.map(formatDate) ?? "nil") " +
            "lines=\(lines.map(maskMRZLine).joined(separator: "|")) " +
            "dateCandidates=\(dateCandidateLog(from: lines))"
        )
        #endif
        if let expiry {
            return MRZOCRResult(foundMRZ: true, expiryDate: expiry)
        }
        return MRZOCRResult(foundMRZ: foundMRZ, expiryDate: nil)
    }

    private static func extractExpiryDate(from lines: [String]) -> Date? {
        let candidates = lines.filter { line in
            line.contains("IDKHM") || line.contains("I<KHM") || line.contains("KHM") || line.contains("<<")
        }
        for line in candidates {
            let dates = dateCandidates(in: line)
            if dates.count >= 2 {
                return dates[1].date
            }
        }

        let combinedDates = candidates.flatMap(dateCandidates)
        if combinedDates.count >= 2 {
            return combinedDates[1].date
        }

        for line in candidates + lines {
            let dates = dateCandidates(in: line)
            if dates.count >= 2 {
                return dates[1].date
            }
        }
        return nil
    }

    private static func dateCandidates(in line: String) -> [MRZDateCandidate] {
        let compact = line.filter { $0.isLetter || $0.isNumber || $0 == "<" }
        let digits = Array(compact)
        guard digits.count >= 6 else { return [] }
        var candidates: [MRZDateCandidate] = []
        for index in 0...(digits.count - 6) {
            let value = String(digits[index..<(index + 6)])
            guard value.allSatisfy(\.isNumber),
                  let date = parseMRZDate(value),
                  yearIsReasonable(date)
            else { continue }
            candidates.append(MRZDateCandidate(raw: value, date: date, offset: index))
        }
        return candidates
    }

    private static func dateCandidateLog(from lines: [String]) -> String {
        let values = lines.flatMap(dateCandidates).map { candidate in
            "\(candidate.raw)->\(formatDate(candidate.date))@\(candidate.offset)"
        }
        return values.isEmpty ? "none" : values.joined(separator: ",")
    }

    private static func maskMRZLine(_ line: String) -> String {
        line.map { character in
            if character.isNumber { return "#" }
            if character.isLetter, character != "K" && character != "H" && character != "M" && character != "I" && character != "D" {
                return "X"
            }
            return character
        }
        .map(String.init)
        .joined()
    }

    private static func legacyExtractExpiryDate(from lines: [String]) -> Date? {
        for line in lines {
            let compact = line.filter { $0.isLetter || $0.isNumber || $0 == "<" }
            let digits = Array(compact)
            guard digits.count >= 14 else { continue }
            for index in 0...(digits.count - 6) {
                let value = String(digits[index..<(index + 6)])
                guard value.allSatisfy(\.isNumber), let date = parseMRZDate(value), yearIsReasonable(date) else { continue }
                return date
            }
        }
        return nil
    }

    private static func normalizeMRZLine(_ raw: String) -> String {
        raw.uppercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "«", with: "<")
            .replacingOccurrences(of: "‹", with: "<")
            .replacingOccurrences(of: "O", with: "0")
    }

    private static func parseMRZDate(_ yymmdd: String) -> Date? {
        guard yymmdd.count == 6, yymmdd.allSatisfy(\.isNumber) else { return nil }
        let chars = Array(yymmdd)
        guard let yy = Int(String(chars[0...1])),
              let month = Int(String(chars[2...3])),
              let day = Int(String(chars[4...5]))
        else { return nil }
        var components = DateComponents()
        components.year = 2000 + yy
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == components.year,
              roundTrip.month == month,
              roundTrip.day == day
        else { return nil }
        return date
    }

    private static func yearIsReasonable(_ date: Date) -> Bool {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        return year >= 2020 && year <= 2099
    }

    private static func isExpired(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.startOfDay(for: date) < calendar.startOfDay(for: Date())
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[NID][PROCESS] \(message)")
        #endif
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.3f", Double(value))
    }

    private static func format(_ point: CGPoint) -> String {
        "(\(format(point.x)),\(format(point.y)))"
    }
}

private struct MRZOCRResult {
    let foundMRZ: Bool
    let expiryDate: Date?
}

private struct MRZDateCandidate {
    let raw: String
    let date: Date
    let offset: Int
}

private extension UIImage {
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
