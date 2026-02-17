import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// High-performance vector similarity search using Apple Accelerate.
/// - Linear scan with vDSP optimized dot product (<5ms for 2000 vectors)
/// - Cosine similarity: dot(A, B) since vectors are L2 normalized
@MainActor
public final class VectorSearchService: Sendable {

    public init() {}

    /// Find k most similar vectors to query
    /// - Parameters:
    ///   - query: The query vector (L2 normalized)
    ///   - vectors: Candidate vectors to search (L2 normalized)
    ///   - topK: Maximum number of results to return
    /// - Returns: Array of (index, similarity) tuples sorted by similarity descending
    public func findSimilar(
        query: [Double],
        vectors: [[Double]],
        topK: Int
    ) -> [(index: Int, similarity: Double)] {
        guard !vectors.isEmpty else { return [] }

        #if canImport(Accelerate)
        return findSimilarAccelerate(query: query, vectors: vectors, topK: topK)
        #else
        return findSimilarFallback(query: query, vectors: vectors, topK: topK)
        #endif
    }

    /// Compute cosine similarity between two L2-normalized vectors
    public func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }

        #if canImport(Accelerate)
        var result: Double = 0.0
        vDSP_dotprD(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
        #else
        return zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
        #endif
    }

    /// Batch compute similarities for all vectors against a query
    public func batchSimilarities(
        query: [Double],
        vectors: [[Double]]
    ) -> [Double] {
        #if canImport(Accelerate)
        return vectors.map { vector in
            var result: Double = 0.0
            vDSP_dotprD(query, 1, vector, 1, &result, vDSP_Length(query.count))
            return result
        }
        #else
        return vectors.map { vector in
            zip(query, vector).reduce(0.0) { $0 + $1.0 * $1.1 }
        }
        #endif
    }

    // MARK: - Private Accelerate Implementation

    #if canImport(Accelerate)
    private func findSimilarAccelerate(
        query: [Double],
        vectors: [[Double]],
        topK: Int
    ) -> [(index: Int, similarity: Double)] {
        let similarities = batchSimilarities(query: query, vectors: vectors)
        let indexed = similarities.enumerated().map { ($0.offset, $0.element) }
        let sorted = indexed.sorted { $0.1 > $1.1 }
        return Array(sorted.prefix(topK))
    }
    #endif

    // MARK: - Fallback Implementation (Linux tests)

    private func findSimilarFallback(
        query: [Double],
        vectors: [[Double]],
        topK: Int
    ) -> [(index: Int, similarity: Double)] {
        let similarities = vectors.enumerated().map { (index, vector) in
            let similarity = zip(query, vector).reduce(0.0) { $0 + $1.0 * $1.1 }
            return (index, similarity)
        }
        return Array(similarities.sorted { $0.1 > $1.1 }.prefix(topK))
    }
}
