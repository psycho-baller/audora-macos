import XCTest
@testable import audora

@MainActor
final class WritingAwarenessManagerLearningWordTests: XCTestCase {
    func testSaveLearningWordFamilyCreatesSharedFamilyRules() throws {
        let (manager, storageManager) = makeManager()
        let draft = LearningWordFamilyDraft(
            familyID: nil,
            targetRuleID: nil,
            targetTerm: " compelling ",
            suggestions: [
                LearningWordSuggestion(
                    term: "good",
                    useWhen: "Use the stronger target when the sentence needs sharper praise.",
                    caution: "Skip it when the claim is mild."
                ),
                LearningWordSuggestion(
                    term: "interesting",
                    useWhen: "",
                    caution: ""
                )
            ],
            suggestedSuggestions: [],
            sourceApp: "Notes",
            contextLabel: "Draft",
            origin: "service",
            anchorRect: nil,
            notice: nil
        )

        let result = manager.saveLearningWordFamily(draft)
        let familyID = try XCTUnwrap(result.familyID)
        let targetRuleID = try XCTUnwrap(result.ruleID)
        let savedRules = manager.state.manualRules

        XCTAssertEqual(result.status, .saved)
        XCTAssertEqual(result.term, "compelling")
        XCTAssertEqual(savedRules.count, 3)
        XCTAssertEqual(Set(savedRules.map(\.family)), [familyID])

        let targetRule = try XCTUnwrap(savedRules.first(where: { $0.id == targetRuleID }))
        XCTAssertEqual(targetRule.type, .target)
        XCTAssertEqual(targetRule.term, "compelling")
        XCTAssertEqual(targetRule.family, familyID)
        XCTAssertEqual(targetRule.source, .manual)
        XCTAssertTrue(targetRule.active)
        XCTAssertTrue(targetRule.pinned)
        XCTAssertEqual(targetRule.priority, 5)
        XCTAssertEqual(targetRule.contexts, [])

        let avoidRules = savedRules.filter { $0.type == .avoid }
        XCTAssertEqual(avoidRules.map(\.term).sorted(), ["good", "interesting"])
        XCTAssertTrue(avoidRules.allSatisfy { $0.family == familyID })
        XCTAssertTrue(avoidRules.allSatisfy { $0.replacementOptions.first?.word == "compelling" })

        let persistedRules = storageManager.loadState().manualRules
        XCTAssertEqual(persistedRules.count, 3)
    }

    func testPrepareLearningWordDraftUsesAISuggestionsAsCandidateTags() async throws {
        let (manager, _) = makeManager(
            suggestionGenerator: { _, _, _, _, _ in
                [
                    LearningWordSuggestion(
                        term: "good",
                        useWhen: "Use the target when a vague positive adjective is too weak.",
                        caution: "Skip it when the sentence should stay understated."
                    ),
                    LearningWordSuggestion(
                        term: "interesting",
                        useWhen: "Use the target when generic interest is not specific enough.",
                        caution: "Do not force it into neutral contexts."
                    )
                ]
            }
        )

        await manager.prepareLearningWordDraftAsync(
            term: "compelling",
            sourceApp: "Notes",
            contextLabel: "Draft",
            origin: "service",
            anchorRect: nil
        )

        let draft = try XCTUnwrap(manager.consumePendingLearningWordFamilyDraft())

        XCTAssertTrue(draft.suggestions.isEmpty)
        XCTAssertEqual(draft.suggestedSuggestions.map(\.term), ["good", "interesting"])
    }

    func testPrepareLearningWordDraftReusesExistingFamilyWithoutRegenerating() async throws {
        var generatorCallCount = 0
        let (manager, _) = makeManager(
            suggestionGenerator: { _, _, _, _, _ in
                generatorCallCount += 1
                return []
            }
        )

        let saveResult = manager.saveLearningWordFamily(
            LearningWordFamilyDraft(
                familyID: nil,
                targetRuleID: nil,
                targetTerm: "compelling",
                suggestions: [
                    LearningWordSuggestion(
                        term: "good",
                        useWhen: "Use the target when you need a more exact positive description.",
                        caution: "Do not overstate the point."
                    ),
                    LearningWordSuggestion(
                        term: "interesting",
                        useWhen: "Use the target when generic interest is too weak.",
                        caution: "Leave it alone when the sentence is neutral."
                    )
                ],
                suggestedSuggestions: [],
                sourceApp: "Notes",
                contextLabel: "Draft",
                origin: "service",
                anchorRect: nil,
                notice: nil
            )
        )

        await manager.prepareLearningWordDraftAsync(
            term: "compelling",
            sourceApp: "Notes",
            contextLabel: "Draft",
            origin: "service",
            anchorRect: nil
        )

        let reopenedDraft = try XCTUnwrap(manager.consumePendingLearningWordFamilyDraft())

        XCTAssertEqual(generatorCallCount, 0)
        XCTAssertEqual(reopenedDraft.familyID, saveResult.familyID)
        XCTAssertEqual(reopenedDraft.targetRuleID, saveResult.ruleID)
        XCTAssertEqual(reopenedDraft.targetTerm, "compelling")
        XCTAssertEqual(reopenedDraft.suggestions.map(\.term), ["good", "interesting"])
    }

    func testGenerateLearningWordSuggestionsRanksHistoryMatchesAndFiltersInvalidTerms() async throws {
        var state = WritingAwarenessState.empty()
        state.mutedTerms = ["nice"]

        let (manager, _) = makeManager(
            state: state,
            suggestionGenerator: { _, _, _, _, _ in
                [
                    LearningWordSuggestion(
                        term: "interesting",
                        useWhen: "Use the target when plain interest feels too generic.",
                        caution: ""
                    ),
                    LearningWordSuggestion(
                        term: "good",
                        useWhen: "",
                        caution: ""
                    ),
                    LearningWordSuggestion(
                        term: "compelling",
                        useWhen: "Should be filtered because it matches the target.",
                        caution: "n/a"
                    ),
                    LearningWordSuggestion(
                        term: " nice ",
                        useWhen: "Should be filtered because it is muted.",
                        caution: "n/a"
                    ),
                    LearningWordSuggestion(
                        term: "good",
                        useWhen: "Should be filtered because it is a duplicate.",
                        caution: "n/a"
                    ),
                    LearningWordSuggestion(
                        term: " ",
                        useWhen: "Should be filtered because it is blank.",
                        caution: "n/a"
                    )
                ]
            }
        )

        let suggestions = try await manager.generateLearningWordSuggestions(
            for: "compelling",
            sourceApp: "Notes",
            contextLabel: "Draft",
            personalOveruseCounts: [("good", 3)]
        )

        XCTAssertEqual(suggestions.map(\.term), ["good", "interesting"])
        XCTAssertTrue(suggestions[0].matchedPersonalHistory)
        XCTAssertFalse(suggestions[1].matchedPersonalHistory)
        XCTAssertFalse(suggestions[0].useWhen.isEmpty)
        XCTAssertFalse(suggestions[0].caution.isEmpty)
        XCTAssertFalse(suggestions[1].caution.isEmpty)
    }

    func testPrepareLearningWordDraftFallsBackToManualReviewWhenGenerationFails() async throws {
        let (manager, storageManager) = makeManager(
            suggestionGenerator: { _, _, _, _, _ in
                throw WritingAwarenessManager.LearningWordGenerationError.apiKeyMissing
            }
        )

        await manager.prepareLearningWordDraftAsync(
            term: "compelling",
            sourceApp: "Notes",
            contextLabel: "Draft",
            origin: "service",
            anchorRect: nil
        )

        let draft = try XCTUnwrap(manager.consumePendingLearningWordFamilyDraft())

        XCTAssertEqual(draft.targetTerm, "compelling")
        XCTAssertTrue(draft.suggestions.isEmpty)
        XCTAssertTrue(draft.suggestedSuggestions.isEmpty)
        XCTAssertEqual(storageManager.loadState().manualRules.count, 0)
        XCTAssertTrue(draft.notice?.contains("OpenAI key not configured") == true)
    }

    func testDeleteLearningWordFamilyRemovesWholeFamily() throws {
        let (manager, storageManager) = makeManager()
        let saveResult = manager.saveLearningWordFamily(
            LearningWordFamilyDraft(
                familyID: nil,
                targetRuleID: nil,
                targetTerm: "compelling",
                suggestions: [
                    LearningWordSuggestion(
                        term: "good",
                        useWhen: "Use the target when it sharpens praise.",
                        caution: "Skip it when the sentence is casual."
                    ),
                    LearningWordSuggestion(
                        term: "interesting",
                        useWhen: "Use the target when interest is too generic.",
                        caution: "Do not force intensity."
                    )
                ],
                suggestedSuggestions: [],
                sourceApp: "Notes",
                contextLabel: "Draft",
                origin: "service",
                anchorRect: nil,
                notice: nil
            )
        )

        manager.deleteLearningWordFamily(
            familyID: saveResult.familyID,
            targetRuleID: saveResult.ruleID
        )

        XCTAssertTrue(manager.state.manualRules.isEmpty)
        XCTAssertTrue(storageManager.loadState().manualRules.isEmpty)
    }

    private func makeManager(
        state: WritingAwarenessState = .empty(),
        suggestionGenerator: WritingAwarenessManager.LearningWordSuggestionGenerator? = nil
    ) -> (WritingAwarenessManager, WritingAwarenessStorageManager) {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("audora-learning-word-tests-\(UUID().uuidString)", isDirectory: true)
        let storageManager = WritingAwarenessStorageManager(
            rootDirectory: rootDirectory,
            legacyRootDirectory: rootDirectory.appendingPathComponent("Legacy", isDirectory: true)
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        let manager = WritingAwarenessManager(
            seed: .fallback(),
            state: state,
            storageManager: storageManager,
            learningWordSuggestionGenerator: suggestionGenerator,
            revealsLearningWordReview: false
        )
        return (manager, storageManager)
    }
}
