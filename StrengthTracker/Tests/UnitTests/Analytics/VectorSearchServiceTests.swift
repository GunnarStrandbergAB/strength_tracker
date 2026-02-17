import XCTest
import Foundation
@testable import StrengthTrackerShared

/// Tests for VectorSearchService.
/// Verifies cosine similarity, findSimilar ranking, and batch similarity computations
/// using known vector inputs with deterministic expected outputs.
final class VectorSearchServiceTests: XCTestCase {

    // MARK: - cosineSimilarity

    @MainActor
    func test_cosineSimilarity_identicalVectors_returnsOne() async {
        let service = VectorSearchService()
        let similarity = service.cosineSimilarity([1.0, 0.0, 0.0], [1.0, 0.0, 0.0])
        XCTAssertEqual(similarity, 1.0, accuracy: 1e-10)
    }

    @MainActor
    func test_cosineSimilarity_identicalNormalized_returnsOne() async {
        let service = VectorSearchService()
        let vec = AnalyticsTestHelpers.l2Normalize([0.5, 0.3, 0.8, 0.1])
        let similarity = service.cosineSimilarity(vec, vec)
        XCTAssertEqual(similarity, 1.0, accuracy: 1e-10)
    }

    @MainActor
    func test_cosineSimilarity_orthogonalVectors_returnsZero() async {
        let service = VectorSearchService()
        let similarity = service.cosineSimilarity([1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
        XCTAssertEqual(similarity, 0.0, accuracy: 1e-10)
    }

    @MainActor
    func test_cosineSimilarity_emptyVectors_returnsZero() async {
        let service = VectorSearchService()
        let similarity = service.cosineSimilarity([], [])
        XCTAssertEqual(similarity, 0.0, accuracy: 1e-10)
    }

    @MainActor
    func test_cosineSimilarity_differentLengthVectors_returnsZero() async {
        let service = VectorSearchService()
        let similarity = service.cosineSimilarity([1.0, 0.0], [1.0, 0.0, 0.0])
        XCTAssertEqual(similarity, 0.0, accuracy: 1e-10)
    }

    @MainActor
    func test_cosineSimilarity_oppositeVectors_returnsNegativeOne() async {
        let service = VectorSearchService()
        let similarity = service.cosineSimilarity([1.0, 0.0, 0.0], [-1.0, 0.0, 0.0])
        XCTAssertEqual(similarity, -1.0, accuracy: 1e-10)
    }

    @MainActor
    func test_cosineSimilarity_knownAngle_returnsExpectedValue() async {
        let service = VectorSearchService()
        let a = AnalyticsTestHelpers.l2Normalize([1.0, 0.0])
        let b = AnalyticsTestHelpers.l2Normalize([1.0, 1.0])
        let similarity = service.cosineSimilarity(a, b)
        XCTAssertEqual(similarity, cos(.pi / 4), accuracy: 1e-6)
    }

    // MARK: - findSimilar

    @MainActor
    func test_findSimilar_returnsTopKResults() async {
        let service = VectorSearchService()
        let vectors: [[Double]] = [
            [1.0, 0.0, 0.0],
            [0.9, 0.1, 0.0],
            [0.0, 1.0, 0.0],
            [0.5, 0.5, 0.0],
        ]
        let results = service.findSimilar(query: [1.0, 0.0, 0.0], vectors: vectors, topK: 2)
        XCTAssertEqual(results.count, 2)
    }

    @MainActor
    func test_findSimilar_sortsBySimilarityDescending() async {
        let service = VectorSearchService()
        let query = AnalyticsTestHelpers.l2Normalize([1.0, 0.0, 0.0])
        let vectors: [[Double]] = [
            AnalyticsTestHelpers.l2Normalize([0.0, 1.0, 0.0]),
            AnalyticsTestHelpers.l2Normalize([0.9, 0.1, 0.0]),
            AnalyticsTestHelpers.l2Normalize([0.5, 0.5, 0.0]),
        ]
        let results = service.findSimilar(query: query, vectors: vectors, topK: 3)

        XCTAssertEqual(results.count, 3)
        for i in 0..<(results.count - 1) {
            XCTAssertGreaterThanOrEqual(
                results[i].similarity,
                results[i + 1].similarity,
                "Results should be sorted by similarity descending"
            )
        }
        XCTAssertEqual(results[0].index, 1)
    }

    @MainActor
    func test_findSimilar_emptyVectors_returnsEmpty() async {
        let service = VectorSearchService()
        let results = service.findSimilar(query: [1.0, 0.0, 0.0], vectors: [], topK: 5)
        XCTAssertTrue(results.isEmpty)
    }

    @MainActor
    func test_findSimilar_topKExceedsCandidateCount_returnsAllCandidates() async {
        let service = VectorSearchService()
        let vectors: [[Double]] = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]]
        let results = service.findSimilar(query: [1.0, 0.0, 0.0], vectors: vectors, topK: 10)
        XCTAssertEqual(results.count, 2)
    }

    @MainActor
    func test_findSimilar_indicesMatchOriginalVectorPositions() async {
        let service = VectorSearchService()
        let query = AnalyticsTestHelpers.l2Normalize([1.0, 0.0, 0.0])
        let vectors: [[Double]] = [
            AnalyticsTestHelpers.l2Normalize([0.0, 0.0, 1.0]),
            AnalyticsTestHelpers.l2Normalize([0.8, 0.2, 0.0]),
            AnalyticsTestHelpers.l2Normalize([0.5, 0.5, 0.0]),
        ]
        let results = service.findSimilar(query: query, vectors: vectors, topK: 3)
        XCTAssertEqual(results[0].index, 1)
    }

    // MARK: - batchSimilarities

    @MainActor
    func test_batchSimilarities_computesAllPairs() async {
        let service = VectorSearchService()
        let vectors: [[Double]] = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
        let similarities = service.batchSimilarities(query: [1.0, 0.0, 0.0], vectors: vectors)

        XCTAssertEqual(similarities.count, 3)
        XCTAssertEqual(similarities[0], 1.0, accuracy: 1e-10)
        XCTAssertEqual(similarities[1], 0.0, accuracy: 1e-10)
        XCTAssertEqual(similarities[2], 0.0, accuracy: 1e-10)
    }

    @MainActor
    func test_batchSimilarities_emptyVectors_returnsEmpty() async {
        let service = VectorSearchService()
        let similarities = service.batchSimilarities(query: [1.0, 0.0, 0.0], vectors: [])
        XCTAssertTrue(similarities.isEmpty)
    }

    @MainActor
    func test_batchSimilarities_normalizedVectors_valuesInExpectedRange() async {
        let service = VectorSearchService()
        let query = AnalyticsTestHelpers.l2Normalize([0.6, 0.3, 0.1])
        let vectors: [[Double]] = [
            AnalyticsTestHelpers.l2Normalize([0.6, 0.3, 0.1]),
            AnalyticsTestHelpers.l2Normalize([0.1, 0.8, 0.1]),
            AnalyticsTestHelpers.l2Normalize([0.2, 0.2, 0.6]),
        ]
        let similarities = service.batchSimilarities(query: query, vectors: vectors)

        XCTAssertEqual(similarities.count, 3)
        XCTAssertEqual(similarities[0], 1.0, accuracy: 1e-10)
        for sim in similarities {
            XCTAssertGreaterThanOrEqual(sim, -1.0 - 1e-10)
            XCTAssertLessThanOrEqual(sim, 1.0 + 1e-10)
        }
    }
}
