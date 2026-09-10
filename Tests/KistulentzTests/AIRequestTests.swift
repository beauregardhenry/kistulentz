import Foundation
import XCTest
@testable import Kistulentz

final class AIRequestTests: XCTestCase {
    override func tearDown() {
        AIRequestMockURLProtocol.handler = nil
        DelayedOllamaURLProtocol.reset()
        super.tearDown()
    }

    func testPreviewIncludesOnlyEnabledOptionalMaterial() {
        var preview = AIRequestPreview(
            purpose: .polish(targetGrade: 8),
            provider: .openAI,
            model: "test-model",
            primaryLabel: "Draft",
            primaryText: "# Chapter\n\nThe draft.",
            styleGuide: "Prefer concrete language.",
            includesStyleGuide: true,
            referenceContext: "<reference_excerpts>Sample</reference_excerpts>",
            includesReferenceContext: false,
            sourceRange: nil,
            sourceText: nil
        )

        XCTAssertTrue(preview.input.contains("Prefer concrete language."))
        XCTAssertFalse(preview.input.contains("Sample"))

        preview.includesStyleGuide = false
        preview.includesReferenceContext = true
        XCTAssertFalse(preview.input.contains("Prefer concrete language."))
        XCTAssertTrue(preview.input.contains("Sample"))
    }

    func testSelectionReplacementRequiresTheOriginalPassageToBeUnchanged() {
        let text = "Before 🌊 passage after."
        let range = (text as NSString).range(of: "🌊 passage")

        XCTAssertEqual(
            SelectionReplacementPlanner.replace(
                in: text,
                range: range,
                expected: "🌊 passage",
                with: "clear passage"
            ),
            "Before clear passage after."
        )
        XCTAssertNil(SelectionReplacementPlanner.replace(
            in: "Before changed passage after.",
            range: range,
            expected: "🌊 passage",
            with: "clear passage"
        ))
    }

    @MainActor
    func testOllamaIsReadyWithAChosenModelAndNoAPIKey() throws {
        let suite = "AIRequestSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        settings.ollamaModel = "local-model:latest"

        XCTAssertTrue(settings.isProviderReady(.ollama))
        XCTAssertNil(settings.apiKey(for: .ollama))
        XCTAssertTrue(AIProvider.ollama.isLocal)
    }

    @MainActor
    func testProviderModelCatalogDefaultsAndPreservesCustomModels() throws {
        let suite = "AIModelCatalogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.openAIModel, AIModelCatalog.recommendedModel(for: .openAI))
        XCTAssertEqual(settings.anthropicModel, AIModelCatalog.recommendedModel(for: .anthropic))
        XCTAssertTrue(AIModelCatalog.openAI.contains { $0.id == settings.openAIModel })
        XCTAssertTrue(AIModelCatalog.anthropic.contains { $0.id == settings.anthropicModel })

        settings.openAIModel = "future-openai-model"
        settings.anthropicModel = "future-anthropic-model"

        let reopened = AppSettings(defaults: defaults)
        XCTAssertEqual(reopened.openAIModel, "future-openai-model")
        XCTAssertEqual(reopened.anthropicModel, "future-anthropic-model")
    }

    func testProviderModelCatalogIdentifiersAreUnique() {
        for provider in [AIProvider.openAI, .anthropic] {
            let choices = AIModelCatalog.choices(for: provider)
            XCTAssertEqual(Set(choices.map(\.id)).count, choices.count)
            XCTAssertEqual(choices.filter(\.isRecommended).count, 1)
        }
    }

    func testDetectsModelsFromTheLocalOllamaTagsEndpoint() async throws {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/tags")
            let body: [String: Any] = [
                "models": [
                    ["name": "gemma3:latest", "model": "gemma3:latest"],
                    ["name": "llama3.2:latest", "model": "llama3.2:latest"]
                ]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: body)
            )
        }

        let models = try await OllamaService(session: session).installedModels()

        XCTAssertEqual(models, ["gemma3:latest", "llama3.2:latest"])
    }

    func testOllamaModelDiscoveryHandlesEmptyAndDuplicateModelLists() async throws {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            let body: [String: Any] = [
                "models": [
                    ["name": "writer:latest", "model": "writer:latest"],
                    ["name": "writer:latest", "model": "writer:latest"],
                    ["name": "", "model": ""]
                ]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: body)
            )
        }
        let deduplicated = try await OllamaService(session: session).installedModels()
        XCTAssertEqual(deduplicated, ["writer:latest"])

        AIRequestMockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"models":[]}"#.utf8)
            )
        }
        let empty = try await OllamaService(session: session).installedModels()
        XCTAssertEqual(empty, [])
    }

    func testOllamaModelDiscoveryMapsMalformedAndUnavailableResponsesToUnavailable() async {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("not-json".utf8)
            )
        }
        do {
            _ = try await OllamaService(session: session).installedModels()
            XCTFail("Malformed model discovery must fail.")
        } catch let error as WritingAIError {
            guard case .ollamaUnavailable = error else {
                return XCTFail("Expected ollamaUnavailable, received \(error).")
            }
        } catch {
            XCTFail("Expected WritingAIError, received \(error).")
        }

        AIRequestMockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        do {
            _ = try await OllamaService(session: session).installedModels()
            XCTFail("An unavailable Ollama service must fail.")
        } catch let error as WritingAIError {
            guard case .ollamaUnavailable = error else {
                return XCTFail("Expected ollamaUnavailable, received \(error).")
            }
        } catch {
            XCTFail("Expected WritingAIError, received \(error).")
        }
    }

    @MainActor
    func testDownloadsRecommendedOllamaModelWithStreamingProgress() async throws {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/pull")
            XCTAssertEqual(request.httpMethod, "POST")
            let data = try XCTUnwrap(request.bodyData)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, OllamaService.recommendedWritingModel)
            XCTAssertEqual(body["stream"] as? Bool, true)
            let response = """
            {"status":"pulling manifest"}
            {"status":"downloading","completed":50,"total":100}
            {"status":"success","completed":100,"total":100}

            """
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(response.utf8)
            )
        }
        var progress: [OllamaPullProgress] = []

        try await OllamaService(session: session).pullModel(
            OllamaService.recommendedWritingModel
        ) { progress.append($0) }

        XCTAssertEqual(progress.count, 3)
        XCTAssertEqual(progress.last?.status, "success")
        XCTAssertEqual(progress.last?.fractionCompleted, 1)
    }

    @MainActor
    func testOllamaModelDownloadRejectsIncompleteAndInvalidResponses() async throws {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            let response = #"{"status":"downloading","completed":50,"total":100}"#
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(response.utf8)
            )
        }

        do {
            try await OllamaService(session: session).pullModel("test:4b") { _ in }
            XCTFail("An interrupted model pull must not be reported as successful.")
        } catch let error as OllamaSetupError {
            guard case .incompleteDownload = error else {
                return XCTFail("Expected incompleteDownload, received \(error).")
            }
        }

        AIRequestMockURLProtocol.handler = { request in
            let response = "not-json\n"
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(response.utf8)
            )
        }
        do {
            try await OllamaService(session: session).pullModel("test:4b") { _ in }
            XCTFail("Malformed progress must be rejected.")
        } catch let error as WritingAIError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, received \(error).")
            }
        }
    }

    @MainActor
    func testOllamaModelDownloadCanBeCancelled() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedOllamaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let task = Task {
            try await OllamaService(session: session).pullModel("test:4b") { _ in }
        }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            try await task.value
            XCTFail("A cancelled model pull must not finish successfully.")
        } catch is CancellationError {
            XCTAssertTrue(DelayedOllamaURLProtocol.wasStopped)
        }
    }

    @MainActor
    func testOllamaModelDownloadRejectsUnsafeModelNameBeforeNetworking() async {
        do {
            try await OllamaService(session: mockSession()).pullModel("bad model\nname") { _ in }
            XCTFail("Unsafe model names must be rejected.")
        } catch let error as OllamaSetupError {
            guard case .invalidModelName = error else {
                return XCTFail("Expected invalidModelName, received \(error).")
            }
        } catch {
            XCTFail("Expected an OllamaSetupError, received \(error).")
        }
    }

    @MainActor
    func testOllamaModelDownloadSurfacesHTTPFailure() async throws {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        do {
            try await OllamaService(session: session).pullModel("test:4b") { _ in }
            XCTFail("An HTTP failure must not be reported as a successful model download.")
        } catch let error as WritingAIError {
            guard case let .api(status, message) = error else {
                return XCTFail("Expected an API error, received \(error).")
            }
            XCTAssertEqual(status, 503)
            XCTAssertTrue(message.contains("test:4b"))
        }
    }

    @MainActor
    func testOllamaModelDownloadSurfacesStreamingServerError() async throws {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"error":"model manifest not found"}"#.utf8)
            )
        }

        do {
            try await OllamaService(session: session).pullModel("missing:4b") { _ in }
            XCTFail("A server-reported pull error must not be treated as success.")
        } catch let error as WritingAIError {
            guard case let .api(status, message) = error else {
                return XCTFail("Expected an API error, received \(error).")
            }
            XCTAssertEqual(status, 200)
            XCTAssertEqual(message, "model manifest not found")
        }
    }

    func testOllamaProgressFractionIsClampedAndHandlesMissingTotals() {
        XCTAssertEqual(
            OllamaPullProgress(status: "downloading", completedBytes: 150, totalBytes: 100)
                .fractionCompleted,
            1
        )
        XCTAssertEqual(
            OllamaPullProgress(status: "downloading", completedBytes: -10, totalBytes: 100)
                .fractionCompleted,
            0
        )
        XCTAssertNil(
            OllamaPullProgress(status: "downloading", completedBytes: 10, totalBytes: 0)
                .fractionCompleted
        )
        XCTAssertNil(
            OllamaPullProgress(status: "downloading", completedBytes: nil, totalBytes: nil)
                .fractionCompleted
        )
    }

    func testOllamaIsSelectedOnlyAfterTheDownloadedModelIsDetected() throws {
        XCTAssertEqual(
            try OllamaSetupVerifier.verifyDownloadedModel("writer:4b", in: ["other:latest", "writer:4b"]),
            "writer:4b"
        )
        XCTAssertThrowsError(
            try OllamaSetupVerifier.verifyDownloadedModel("writer:4b", in: ["other:latest"])
        ) { error in
            guard case OllamaSetupError.modelNotVerified = error else {
                return XCTFail("Expected modelNotVerified, received \(error).")
            }
        }
    }

    func testOllamaRewriteUsesStructuredNonStreamingLocalRequest() async throws {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/chat")
            let data = try XCTUnwrap(request.bodyData)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, "local-model")
            XCTAssertEqual(body["stream"] as? Bool, false)
            XCTAssertNotNil(body["format"] as? [String: Any])
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])

            let result = """
            {"alternatives":[
              {"text":"First.","explanation":"Direct.","gradeEstimate":5},
              {"text":"Second.","explanation":"Compact.","gradeEstimate":5.5},
              {"text":"Third.","explanation":"Rhythmic.","gradeEstimate":6}
            ]}
            """
            let response: [String: Any] = [
                "message": ["role": "assistant", "content": result]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: response)
            )
        }

        let goal = SelectionRewriteGoal(kind: .shorten, requestedTone: nil)
        let preview = AIRequestPreview(
            purpose: .selectionRewrite(goal: goal, targetGrade: 8),
            provider: .ollama,
            model: "local-model",
            primaryLabel: "Selection",
            primaryText: "This is a longer selection.",
            styleGuide: nil,
            includesStyleGuide: false,
            referenceContext: nil,
            includesReferenceContext: false,
            sourceRange: NSRange(location: 0, length: 27),
            sourceText: "This is a longer selection."
        )

        let result = try await SelectionRewriteService(session: session).rewrite(
            request: preview,
            apiKey: nil
        )

        XCTAssertEqual(result.alternatives.count, 3)
        XCTAssertEqual(result.alternatives.first?.text, "First.")
    }

    func testRewriteRejectsAProviderResponseWithoutThreeAlternatives() async throws {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            let result = """
            {"alternatives":[
              {"text":"First.","explanation":"Direct.","gradeEstimate":5},
              {"text":"Second.","explanation":"Compact.","gradeEstimate":5.5}
            ]}
            """
            let response: [String: Any] = [
                "message": ["role": "assistant", "content": result]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: response)
            )
        }
        let preview = AIRequestPreview(
            purpose: .selectionRewrite(
                goal: SelectionRewriteGoal(kind: .shorten, requestedTone: nil),
                targetGrade: 8
            ),
            provider: .ollama,
            model: "local-model",
            primaryLabel: "Selection",
            primaryText: "A passage to shorten.",
            styleGuide: nil,
            includesStyleGuide: false,
            referenceContext: nil,
            includesReferenceContext: false,
            sourceRange: NSRange(location: 0, length: 21),
            sourceText: "A passage to shorten."
        )

        do {
            _ = try await SelectionRewriteService(session: session).rewrite(
                request: preview,
                apiKey: nil
            )
            XCTFail("An incomplete alternative set should be rejected.")
        } catch let error as WritingAIError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, received \(error).")
            }
        }
    }

    @MainActor
    func testAIReviewSurvivesKnownApplyUndoAndRedoTextStates() async throws {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            let review = #"{"summary":"Clearer.","gradeEstimate":5,"polishedText":"We moved fast.","suggestions":[{"original":"quickly","replacement":"fast","explanation":"Use a direct word.","category":"concision"}]}"#
            let body: [String: Any] = [
                "message": ["role": "assistant", "content": review]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: body)
            )
        }

        let suite = "AIReviewUndoTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.provider = .ollama
        settings.ollamaModel = "local-model"

        let original = "We moved quickly."
        let accepted = "We moved fast."
        let viewModel = EditorViewModel(service: WritingAIService(session: session))
        viewModel.configureDocument(url: nil, text: original)
        let request = AIRequestPreview(
            purpose: .polish(targetGrade: 8),
            provider: .ollama,
            model: "local-model",
            primaryLabel: "Markdown draft",
            primaryText: original,
            styleGuide: nil,
            includesStyleGuide: false,
            referenceContext: nil,
            includesReferenceContext: false,
            sourceRange: nil,
            sourceText: original
        )

        viewModel.runAIReview(request: request, matching: original, settings: settings)
        while viewModel.isReviewing { await Task.yield() }
        XCTAssertNotNil(viewModel.aiReview)
        XCTAssertEqual(viewModel.aiIssues.count, 1)

        viewModel.preserveAIReview(afterApplying: accepted)
        viewModel.scheduleAnalysis(text: original, targetGrade: 8, immediately: true)
        XCTAssertNotNil(viewModel.aiReview)
        XCTAssertEqual(viewModel.aiIssues.count, 1)

        viewModel.scheduleAnalysis(text: accepted, targetGrade: 8, immediately: true)
        XCTAssertNotNil(viewModel.aiReview)
        XCTAssertTrue(viewModel.aiIssues.isEmpty)

        viewModel.scheduleAnalysis(text: "A manually changed draft.", targetGrade: 8, immediately: true)
        XCTAssertNil(viewModel.aiReview)
    }

    @MainActor
    func testSelectionRewritePublishesThreeAlternativesAndClearsBusyState() async throws {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            let result = #"{"alternatives":[{"text":"We ran.","explanation":"Direct.","gradeEstimate":2},{"text":"We hurried.","explanation":"Specific.","gradeEstimate":3},{"text":"We moved fast.","explanation":"Natural.","gradeEstimate":3.5}]}"#
            let body: [String: Any] = ["message": ["role": "assistant", "content": result]]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: body)
            )
        }
        let (settings, suite) = try ollamaSettings()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let source = "We moved very quickly."
        let range = (source as NSString).range(of: source)
        let request = rewriteRequest(source: source, range: range)
        let viewModel = EditorViewModel(rewriteService: SelectionRewriteService(session: session))

        viewModel.runSelectionRewrite(request: request, settings: settings)
        await waitUntil { !viewModel.isRewriting }

        let presentation = try XCTUnwrap(viewModel.rewritePresentation)
        XCTAssertEqual(presentation.sourceRange, range)
        XCTAssertEqual(presentation.sourceText, source)
        XCTAssertEqual(presentation.alternatives.map(\.text), ["We ran.", "We hurried.", "We moved fast."])
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testSelectionRewriteFailureClearsBusyStateAndReportsAnActionableError() async throws {
        let session = mockSession()
        AIRequestMockURLProtocol.handler = { request in
            let body: [String: Any] = ["message": ["role": "assistant", "content": "not valid JSON"]]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try JSONSerialization.data(withJSONObject: body)
            )
        }
        let (settings, suite) = try ollamaSettings()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let source = "A passage."
        let viewModel = EditorViewModel(rewriteService: SelectionRewriteService(session: session))

        viewModel.runSelectionRewrite(
            request: rewriteRequest(source: source, range: (source as NSString).range(of: source)),
            settings: settings
        )
        await waitUntil { !viewModel.isRewriting }

        XCTAssertNil(viewModel.rewritePresentation)
        XCTAssertEqual(viewModel.errorMessage, WritingAIError.invalidResponse.localizedDescription)
    }

    @MainActor
    func testEditingWhileAIReviewIsRunningCancelsItAndIgnoresItsStaleResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedOllamaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let (settings, suite) = try ollamaSettings()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let original = "The original draft."
        let request = AIRequestPreview(
            purpose: .polish(targetGrade: 8), provider: .ollama, model: "local-model",
            primaryLabel: "Draft", primaryText: original, styleGuide: nil,
            includesStyleGuide: false, referenceContext: nil, includesReferenceContext: false,
            sourceRange: nil, sourceText: original
        )
        let viewModel = EditorViewModel(service: WritingAIService(session: session))
        viewModel.configureDocument(url: nil, text: original)

        viewModel.runAIReview(request: request, matching: original, settings: settings)
        XCTAssertTrue(viewModel.isReviewing)
        viewModel.scheduleAnalysis(text: "The author changed the draft.", targetGrade: 8, immediately: true)
        await waitUntil { DelayedOllamaURLProtocol.wasStopped }

        XCTAssertFalse(viewModel.isReviewing)
        XCTAssertNil(viewModel.aiReview)
        XCTAssertTrue(viewModel.aiIssues.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testEditingWhileSelectionRewriteIsRunningCancelsItAndKeepsNoStalePresentation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedOllamaURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let (settings, suite) = try ollamaSettings()
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let source = "The selected passage."
        let viewModel = EditorViewModel(rewriteService: SelectionRewriteService(session: session))

        viewModel.runSelectionRewrite(
            request: rewriteRequest(source: source, range: (source as NSString).range(of: source)),
            settings: settings
        )
        XCTAssertTrue(viewModel.isRewriting)
        viewModel.scheduleAnalysis(text: "A changed document.", targetGrade: 8, immediately: true)
        await waitUntil { DelayedOllamaURLProtocol.wasStopped }

        XCTAssertFalse(viewModel.isRewriting)
        XCTAssertNil(viewModel.rewritePresentation)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testReferenceAndFocusStateCanBeAppliedReplacedAndCleared() {
        let reference = EPUBReference(
            fileName: "reference.epub", title: "Reference", author: "Author",
            chapters: [ReferenceChapter(id: 1, title: "Opening", text: "A measured opening line.")],
            profile: ReferenceProfile(
                wordCount: 5, chapterCount: 1, gradeLevel: 6, averageSentenceWords: 5,
                sentenceVariation: 0, averageParagraphWords: 5, dialogueRatio: 0,
                firstPersonRatio: 0, thirdPersonRatio: 0, tempo: "measured", voice: "direct",
                tone: ["calm"], vocabulary: [], characters: []
            )
        )
        let viewModel = EditorViewModel()

        viewModel.useReference(reference, draft: "A measured draft line.")
        XCTAssertEqual(viewModel.referenceBook?.id, reference.id)
        viewModel.focus(on: NSRange(location: 2, length: 4))
        XCTAssertEqual(viewModel.focusRequest?.range, NSRange(location: 2, length: 4))

        viewModel.clearReference()
        XCTAssertNil(viewModel.referenceBook)
        XCTAssertEqual(viewModel.referenceAlignment.score, 0)
        XCTAssertTrue(viewModel.referenceAlignment.issues.isEmpty)
        XCTAssertFalse(viewModel.isLoadingReference)
    }

    @MainActor
    func testLearnedAdvisoryDecisionImmediatelyFiltersVisibleLocalIssue() async {
        let text = "We moved quickly toward the door."
        let viewModel = EditorViewModel()
        viewModel.configureDocument(url: nil, text: text)
        viewModel.scheduleAnalysis(text: text, targetGrade: 8, immediately: true)
        await waitUntil { viewModel.analysis.stats.words > 0 }
        guard let issue = viewModel.visibleLocalIssues.first(where: { $0.category == .adverb }) else {
            return XCTFail("Expected the local adverb rule to flag 'quickly'.")
        }
        let decision = ProjectStyleDecision(
            action: .declined, category: issue.category, excerpt: issue.excerpt,
            replacement: nil, count: ProjectStyleManager.advisorySuppressionThreshold,
            lastUsedAt: Date(), message: issue.message
        )

        viewModel.updateStyleDecisions([decision])

        XCTAssertFalse(viewModel.visibleLocalIssues.contains { $0.id == issue.id })
        XCTAssertFalse(viewModel.allIssues.contains { $0.id == issue.id })
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @MainActor @escaping () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out waiting for editor state to settle.")
    }

    @MainActor
    private func ollamaSettings() throws -> (AppSettings, String) {
        let suite = "EditorViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults)
        settings.provider = .ollama
        settings.ollamaModel = "local-model"
        return (settings, suite)
    }

    private func rewriteRequest(source: String, range: NSRange) -> AIRequestPreview {
        AIRequestPreview(
            purpose: .selectionRewrite(
                goal: SelectionRewriteGoal(kind: .shorten, requestedTone: nil),
                targetGrade: 8
            ),
            provider: .ollama, model: "local-model", primaryLabel: "Selection",
            primaryText: source, styleGuide: nil, includesStyleGuide: false,
            referenceContext: nil, includesReferenceContext: false,
            sourceRange: range, sourceText: source
        )
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIRequestMockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class AIRequestMockURLProtocol: URLProtocol {
    private static let handlerStorage = LockedTestValue<((URLRequest) throws -> (HTTPURLResponse, Data))?>(nil)
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { handlerStorage.value }
        set { handlerStorage.value = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class DelayedOllamaURLProtocol: URLProtocol {
    private static let stoppedStorage = LockedTestValue(false)
    private var workItem: DispatchWorkItem?

    static var wasStopped: Bool {
        stoppedStorage.value
    }

    static func reset() {
        stoppedStorage.value = false
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let response = HTTPURLResponse(
                url: self.request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(#"{"status":"success"}"#.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        self.workItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    override func stopLoading() {
        workItem?.cancel()
        Self.stoppedStorage.value = true
    }
}

private extension URLRequest {
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
