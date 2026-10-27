import Foundation

public enum ResearchUtilities {
    public static func rectangle(_ text: String) throws -> [Int]? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        let values = text.split(separator: ",", omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count == 4, values.allSatisfy({ $0 != nil }) else { throw ResearchError.invalidRectangle }
        return values.map { $0! }
    }
    public static func p95(_ values: [Double]) -> Double? {
        guard !values.isEmpty, values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return values.sorted()[Int(ceil(Double(values.count)*0.95))-1]
    }
    /// FileHandle reads may be short without reaching EOF. Never accept a truncated prefix.
    public static func readBounded(limit: Int, read: (Int) throws -> Data) throws -> Data {
        guard limit >= 0, limit < Int.max else { throw ResearchError.invalidDimensions }
        var result = Data()
        while result.count <= limit {
            let chunk = try read(min(65536, limit+1-result.count))
            if chunk.isEmpty { return result }
            guard chunk.count <= limit-result.count else { throw ResearchError.invalidDimensions }
            result.append(chunk)
        }
        throw ResearchError.invalidDimensions
    }
}

/// A 95% Wilson score interval for a proportion of successes in `trials` independent trials.
/// Unlike the plain normal approximation it stays inside 0...1 and behaves at 0 and `trials` successes.
/// It is only as honest as the trials are independent; callers must say what the trials were.
public struct ProportionInterval: Equatable, Sendable {
    public static let z95 = 1.959963984540054
    public let successes: Int
    public let trials: Int
    public let lower: Double
    public let upper: Double

    public init?(successes: Int, trials: Int, z: Double = ProportionInterval.z95) {
        guard trials > 0, successes >= 0, successes <= trials, z.isFinite, z > 0 else { return nil }
        let n = Double(trials), p = Double(successes) / n, z2 = z * z
        let denominator = 1 + z2 / n
        let center = (p + z2 / (2 * n)) / denominator
        let half = z * (p * (1 - p) / n + z2 / (4 * n * n)).squareRoot() / denominator
        self.successes = successes
        self.trials = trials
        self.lower = max(0, center - half)
        self.upper = min(1, center + half)
    }
}
