/// Semantic failures in a context-free Fusion plan.
public enum FusionPlanValidationError: Error, Sendable, Equatable {
    case noStages
    case emptyStage(index: Int)
    case emptyIdentityField
    case emptyScoreAnnotation
    case emptyIndexName(stage: Int, input: Int)
    case emptyMatchingFields(stage: Int, input: Int)
    case emptyOrdering(stage: Int, input: Int)
    case emptyScoringAnnotation(stage: Int, input: Int)
    case candidatesRequiredInFirstStage(input: Int)
    case noScoredInputs
    case invalidWeight(index: Int)
    case weightCount(expected: Int, actual: Int)
}

extension FusionSource {
    /// Validates semantics that do not require a schema or runtime context.
    public func validate() throws(FusionPlanValidationError) {
        guard !stages.isEmpty else { throw .noStages }
        guard !identityField.isEmpty else { throw .emptyIdentityField }
        guard !scoreAnnotation.isEmpty else { throw .emptyScoreAnnotation }

        var scoredInputCount = 0
        for (stageIndex, stage) in stages.enumerated() {
            guard !stage.inputs.isEmpty else { throw .emptyStage(index: stageIndex) }
            for (inputIndex, input) in stage.inputs.enumerated() {
                if stageIndex == 0, input.requirement == .candidates {
                    throw .candidatesRequiredInFirstStage(input: inputIndex)
                }
                switch input.operation {
                case .index(let source):
                    switch source.selection {
                    case .named(let name, _):
                        guard !name.isEmpty else {
                            throw .emptyIndexName(stage: stageIndex, input: inputIndex)
                        }
                    case .matching(_, let fields, _):
                        guard !fields.isEmpty else {
                            throw .emptyMatchingFields(stage: stageIndex, input: inputIndex)
                        }
                    }
                case .filter:
                    break
                case .order(let keys):
                    guard !keys.isEmpty else {
                        throw .emptyOrdering(stage: stageIndex, input: inputIndex)
                    }
                }
                if case .annotation(let name, _) = input.scoring, name.isEmpty {
                    throw .emptyScoringAnnotation(stage: stageIndex, input: inputIndex)
                }
                if input.scoring != nil {
                    scoredInputCount += 1
                }
            }
        }

        guard scoredInputCount > 0 else { throw .noScoredInputs }
        guard case .weighted(let weights) = strategy else { return }
        guard weights.count == scoredInputCount else {
            throw .weightCount(expected: scoredInputCount, actual: weights.count)
        }
        for (index, weight) in weights.enumerated() where !weight.isFinite || weight < 0 {
            throw .invalidWeight(index: index)
        }
    }
}
