import Foundation

enum VectorMath {
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, a.count > 0 else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        guard normA > 0, normB > 0 else { return 0 }
        return Double(dotProduct / (sqrt(normA) * sqrt(normB)))
    }
}