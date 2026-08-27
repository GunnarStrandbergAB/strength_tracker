#if canImport(SwiftUI)
import SwiftUI
import UIKit
import StrengthTrackerShared

/// Per-frame drag-to-reorder state, isolated from ActiveWorkoutView.body.
///
/// @Observable's per-property, per-execution tracking means only views that READ a
/// property during body evaluation are invalidated when it changes:
/// - `translation` (per touch-move frame) → only ExerciseDragEffect bodies
/// - `targetIndex` (per slot crossing)    → only ExerciseDragEffect bodies
/// - `draggedId` (drag start/end)         → modifiers + ActiveWorkoutView (.scrollDisabled)
/// - `heights` (rare layout changes)      → nothing while idle (modifiers return early
///                                          before reading heights when not dragging)
///
/// This keeps the heavy exercise cards (~60 live text fields on a typical workout)
/// from being rebuilt on every drag frame.
@MainActor
@Observable
final class ExerciseDragState {
    var draggedId: UUID?
    var sourceIndex: Int?
    var translation: CGFloat = 0
    var targetIndex: Int?
    var heights: [UUID: CGFloat] = [:]

    var isDragging: Bool { draggedId != nil }

    func dragChanged(id: UUID, translation: CGFloat, orderedIds: [UUID]) {
        if draggedId == nil {
            draggedId = id
            sourceIndex = orderedIds.firstIndex(of: id)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        self.translation = translation
        guard let source = sourceIndex else { return }
        let proposed = proposedIndex(translation: translation, source: source, ids: orderedIds)
        if proposed != targetIndex {
            // No withAnimation here — the modifier's value-scoped .animation springs
            // the sibling gap, and an ambient transaction would sweep the
            // finger-follow offset into the spring (visible rubber-banding).
            targetIndex = proposed
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// Returns the (source, destination) pair to commit if the drop landed on a
    /// new slot, resetting the drag with a settle animation either way.
    func dragEnded() -> (from: Int, to: Int)? {
        let commit: (from: Int, to: Int)?
        if let source = sourceIndex, let target = targetIndex, source != target {
            commit = (source, target)
        } else {
            commit = nil
        }
        withAnimation(.spring(duration: 0.3)) { reset() }
        return commit
    }

    func reset() {
        draggedId = nil
        sourceIndex = nil
        translation = 0
        targetIndex = nil
    }

    /// Walk cumulative card heights (+ gap) in the drag direction. The crossing
    /// threshold is the neighbor's midpoint CAPPED at 90pt — an 8-set card is
    /// ~620pt tall and its midpoint would demand a physically impossible drag
    /// (scrolling is disabled mid-drag). The 40pt floor guards an unmeasured
    /// height (`?? 0`) from making the walk hypersensitive. After a crossing the
    /// FULL pitch is still subtracted: `remaining` is measured from the new
    /// slot's origin, which depends on geometry, not on the threshold.
    private func proposedIndex(translation: CGFloat, source: Int, ids: [UUID]) -> Int {
        var index = source
        var remaining = translation
        if translation > 0 {
            for i in (source + 1)..<ids.count {
                let pitch = (heights[ids[i]] ?? 0) + STSpacing.cardGap
                guard remaining > Self.crossingThreshold(pitch: pitch) else { break }
                index = i
                remaining -= pitch
            }
        } else {
            for i in stride(from: source - 1, through: 0, by: -1) {
                let pitch = (heights[ids[i]] ?? 0) + STSpacing.cardGap
                guard remaining < -Self.crossingThreshold(pitch: pitch) else { break }
                index = i
                remaining += pitch
            }
        }
        return index
    }

    private static func crossingThreshold(pitch: CGFloat) -> CGFloat {
        min(max(pitch / 2, 40), 90)
    }
}

/// Applies drag offset and pickup styling to one exercise card. The per-frame drag
/// properties are read HERE, in this modifier's body, so touch-move invalidation is
/// confined to these tiny bodies — `content` is an opaque, already-built view and is
/// never re-evaluated by drag updates.
///
/// Deliberately a single linear chain with no structural if/else: branching would
/// change the card's view identity at drag start/end and tear down its live text
/// fields. The finger-follow offset sits AFTER the value-scoped `.animation` so
/// slot-crossing springs can never sweep it; the end-of-drag settle animates via the
/// ambient transaction from `dragEnded()`.
struct ExerciseDragEffect: ViewModifier {
    let id: UUID
    let index: Int
    let dragState: ExerciseDragState

    func body(content: Content) -> some View {
        let isDragged = dragState.draggedId == id
        let gap = gapOffset
        return content
            .offset(y: gap)                                  // siblings open a slot
            .animation(.spring(duration: 0.25), value: gap)  // scopes ONLY the gap
            .offset(y: isDragged ? dragState.translation : 0)
            .scaleEffect(isDragged ? 1.02 : 1)
            .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: 8, y: 4)
            .zIndex(isDragged ? 1 : 0)
    }

    /// Offset that opens a slot for the dragged card. Reads only `draggedId` while
    /// idle, so height writes during normal scrolling invalidate nothing.
    private var gapOffset: CGFloat {
        guard let draggedId = dragState.draggedId, draggedId != id,
              let source = dragState.sourceIndex,
              let target = dragState.targetIndex else { return 0 }
        let draggedHeight = (dragState.heights[draggedId] ?? 0) + STSpacing.cardGap
        if source < target, index > source, index <= target { return -draggedHeight }
        if target < source, index >= target, index < source { return draggedHeight }
        return 0
    }
}

/// Accent border for the active exercise. Reads the view model's observable state
/// in its OWN body, so a tap that changes `activeExerciseId` re-evaluates only
/// these tiny modifiers — not ActiveWorkoutView's whole body with every card.
struct ActiveExerciseHighlight: ViewModifier {
    let exerciseId: UUID
    let viewModel: WorkoutViewModel

    func body(content: Content) -> some View {
        let isActive = viewModel.activeExercise?.id == exerciseId
        return content
            .overlay(
                RoundedRectangle(cornerRadius: STRadius.card)
                    .stroke(STColors.primary, lineWidth: 1.5)
                    .opacity(isActive ? 1 : 0)
            )
            .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}
#endif
