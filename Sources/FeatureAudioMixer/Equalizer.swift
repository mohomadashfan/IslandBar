import Foundation
import IslandAudioDSP

/// Six-band equaliser: low shelf, four peaking bands and a high shelf.
public enum Equalizer {
    public static let frequencies: [Double] = [60, 170, 500, 1500, 4500, 12_000]
    public static let bandLabels = ["60", "170", "500", "1.5k", "4.5k", "12k"]
    public static let peakQ = 1.0

    public enum FilterKind: Sendable {
        case lowShelf, peaking, highShelf
    }

    public static func kind(forBand band: Int) -> FilterKind {
        band == 0 ? .lowShelf : (band == frequencies.count - 1 ? .highShelf : .peaking)
    }

    /// RBJ "Audio EQ Cookbook" biquad, normalised so a0 == 1: [b0, b1, b2, a1, a2].
    public static func coefficients(kind: FilterKind, frequency: Double, gainDB: Double, q: Double = peakQ, sampleRate: Double) -> [Double] {
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let cosW = cos(w0)
        let sinW = sin(w0)
        var b0, b1, b2, a0, a1, a2: Double

        switch kind {
        case .peaking:
            let alpha = sinW / (2 * q)
            b0 = 1 + alpha * a
            b1 = -2 * cosW
            b2 = 1 - alpha * a
            a0 = 1 + alpha / a
            a1 = -2 * cosW
            a2 = 1 - alpha / a
        case .lowShelf, .highShelf:
            // Shelf slope S = 1.
            let alpha = sinW / 2 * sqrt(2)
            let twoSqrtAAlpha = 2 * sqrt(a) * alpha
            if kind == .lowShelf {
                b0 = a * ((a + 1) - (a - 1) * cosW + twoSqrtAAlpha)
                b1 = 2 * a * ((a - 1) - (a + 1) * cosW)
                b2 = a * ((a + 1) - (a - 1) * cosW - twoSqrtAAlpha)
                a0 = (a + 1) + (a - 1) * cosW + twoSqrtAAlpha
                a1 = -2 * ((a - 1) + (a + 1) * cosW)
                a2 = (a + 1) + (a - 1) * cosW - twoSqrtAAlpha
            } else {
                b0 = a * ((a + 1) + (a - 1) * cosW + twoSqrtAAlpha)
                b1 = -2 * a * ((a - 1) + (a + 1) * cosW)
                b2 = a * ((a + 1) + (a - 1) * cosW - twoSqrtAAlpha)
                a0 = (a + 1) - (a - 1) * cosW + twoSqrtAAlpha
                a1 = 2 * ((a - 1) - (a + 1) * cosW)
                a2 = (a + 1) - (a - 1) * cosW - twoSqrtAAlpha
            }
        }
        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
    }

    /// Flattened coefficients for all bands, in the layout the C mixer expects.
    public static func coefficientTable(gains: [Double], sampleRate: Double) -> [Float] {
        (0..<Int(IB_EQ_BANDS)).flatMap { band in
            coefficients(
                kind: kind(forBand: band),
                frequency: frequencies[band],
                gainDB: band < gains.count ? gains[band] : 0,
                sampleRate: sampleRate
            ).map(Float.init)
        }
    }

    /// Headroom so boosted bands do not clip: attenuate by the largest boost.
    public static func preamp(for gains: [Double]) -> Float {
        Float(pow(10, -max(0, gains.max() ?? 0) / 20))
    }

    /// Magnitude response in dB of one biquad at `frequency` (for tests and the curve preview).
    public static func responseDB(_ c: [Double], frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        // H(e^jw) = (b0 + b1 z^-1 + b2 z^-2) / (1 + a1 z^-1 + a2 z^-2)
        let numRe = c[0] + c[1] * cos(-w) + c[2] * cos(-2 * w)
        let numIm = c[1] * sin(-w) + c[2] * sin(-2 * w)
        let denRe = 1 + c[3] * cos(-w) + c[4] * cos(-2 * w)
        let denIm = c[3] * sin(-w) + c[4] * sin(-2 * w)
        let magnitude = sqrt(numRe * numRe + numIm * numIm) / sqrt(denRe * denRe + denIm * denIm)
        return 20 * log10(magnitude)
    }
}
