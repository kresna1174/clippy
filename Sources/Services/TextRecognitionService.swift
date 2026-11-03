import Foundation
import Vision
import AppKit

enum TextRecognitionService {
    /// Performs text recognition on image Data.
    static func recognizeText(from imageData: Data) -> String? {
        guard let image = NSImage(data: imageData) else { return nil }
        return recognizeText(from: image)
    }

    /// Performs text recognition on an NSBitmapImageRep.
    static func recognizeText(from rep: NSBitmapImageRep) -> String? {
        guard let cgImage = rep.cgImage else { return nil }
        return performRecognition(on: cgImage)
    }

    /// Performs text recognition on an NSImage.
    static func recognizeText(from image: NSImage) -> String? {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return performRecognition(on: cgImage)
        }
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let cgImage = rep.cgImage {
            return performRecognition(on: cgImage)
        }
        return nil
    }

    /// Asynchronous variant for background recognition without blocking the UI.
    static func recognizeTextAsync(from imageData: Data, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let text = recognizeText(from: imageData)
            DispatchQueue.main.async {
                completion(text)
            }
        }
    }

    private static func performRecognition(on cgImage: CGImage) -> String? {
        var recognizedLines: [String] = []

        let request = VNRecognizeTextRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            for observation in observations {
                if let candidate = observation.topCandidates(1).first?.string {
                    recognizedLines.append(candidate)
                }
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("[TextRecognitionService] Recognition failed: \(error)")
            return nil
        }

        let fullText = recognizedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return fullText.isEmpty ? nil : fullText
    }
}
