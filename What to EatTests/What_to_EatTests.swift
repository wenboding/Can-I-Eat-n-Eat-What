import XCTest
import UIKit
@testable import What_to_Eat

final class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static var capturedRequest: URLRequest?

    static func setRequestHandler(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        requestHandler = handler
        capturedRequest = nil
        lock.unlock()
    }

    static func lastRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequest
    }

    static func reset() {
        lock.lock()
        requestHandler = nil
        capturedRequest = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.requestHandler
        Self.capturedRequest = request
        Self.lock.unlock()

        guard let handler else {
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

final class What_to_EatTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        MockURLProtocol.reset()
    }

    func testResizeImageMaxDimension() {
        let image = makeImage(size: CGSize(width: 3000, height: 1800))

        let resized = ImageProcessing.resizedImage(image, maxDimension: 1280)

        XCTAssertLessThanOrEqual(max(resized.size.width, resized.size.height), 1280.1)
    }

    func testMealPhotoProcessingUses3840MaxDimension() throws {
        let image = makeImage(size: CGSize(width: 5000, height: 3000))
        let rawData = try XCTUnwrap(image.jpegData(compressionQuality: 1))

        let processed = try ImageProcessing.processImageData(rawData, profile: .mealPhoto)

        XCTAssertLessThanOrEqual(max(processed.image.size.width, processed.image.size.height), 3840.1)
        XCTAssertLessThanOrEqual(processed.dataURL.utf8.count, ImageProcessing.maxDataURIItemBytes)
    }

    func testHealthReportProcessingUses3840MaxDimension() throws {
        let image = makeImage(size: CGSize(width: 6000, height: 4000))
        let rawData = try XCTUnwrap(image.jpegData(compressionQuality: 1))

        let processed = try ImageProcessing.processImageData(rawData, profile: .healthReport)

        XCTAssertLessThanOrEqual(max(processed.image.size.width, processed.image.size.height), 3840.1)
        XCTAssertLessThanOrEqual(processed.dataURL.utf8.count, ImageProcessing.maxDataURIItemBytes)
    }

    func testDataURIItemLimitHelper() {
        let underLimitJPEG = Data(repeating: 0, count: 7_000_000)
        let overLimitJPEG = Data(repeating: 0, count: 8_000_000)

        XCTAssertTrue(ImageProcessing.isWithinDataURIItemLimit(jpegData: underLimitJPEG))
        XCTAssertFalse(ImageProcessing.isWithinDataURIItemLimit(jpegData: overLimitJPEG))
    }

    func testJPEGDataURLFormatting() {
        let image = makeImage(size: CGSize(width: 400, height: 400))
        let data = ImageProcessing.jpegData(from: image, maxDimension: 1280, compressionQuality: 0.8)

        XCTAssertNotNil(data)

        guard let data else {
            return XCTFail("Expected JPEG data")
        }

        let url = ImageProcessing.dataURL(forJPEGData: data)

        XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
        XCTAssertGreaterThan(url.count, "data:image/jpeg;base64,".count)
    }

    func testMealAnalysisDecoding() throws {
        let json = """
        {
          "foods": [{"name": "Grilled chicken", "portion": "150g", "confidence": 0.91}],
          "calories_estimate": 420,
          "macros_estimate": {"protein_g": 40, "carbs_g": 22, "fat_g": 14},
          "diet_flags": ["high_protein"],
          "allergen_warnings": ["none"],
          "notes": "Looks balanced"
        }
        """

        let decoded = try JSONDecoder().decode(MealAnalysis.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.foods.first?.name, "Grilled chicken")
        XCTAssertEqual(decoded.caloriesEstimate, 420)
        XCTAssertEqual(decoded.macrosEstimate.proteinG, 40)
    }

    func testDailySummaryAggregationLogic() {
        let meal1 = MealEntry(
            dateTime: Date(),
            mealType: .lunch,
            caloriesEstimate: 500,
            proteinG: 30,
            carbsG: 50,
            fatG: 20,
            notes: "meal 1"
        )

        let meal2 = MealEntry(
            dateTime: Date(),
            mealType: .dinner,
            caloriesEstimate: 700,
            proteinG: 40,
            carbsG: 60,
            fatG: 25,
            notes: "meal 2"
        )

        let totals = DailySummaryCalculator.aggregate(meals: [meal1, meal2])

        XCTAssertEqual(totals.calories, 1200)
        XCTAssertEqual(totals.macros.proteinG, 70)
        XCTAssertEqual(totals.macros.carbsG, 110)
        XCTAssertEqual(totals.macros.fatG, 45)
    }

    func testRecommendationDecoding() throws {
        let json = """
        {
          "recommended_meal": {
            "title": "Salmon Rice Bowl",
            "why": "High protein and balanced carbs.",
            "nutrition_focus": ["protein", "omega_3"],
            "suggested_ingredients": ["salmon", "brown rice", "broccoli"],
            "estimated_macros": {"protein_g": 38, "carbs_g": 52, "fat_g": 18},
            "estimated_calories": 560
          },
          "nearby_options": [
            {"name": "Fresh Bowl", "reason": "Good lean protein options", "distance_miles": 1.2}
          ]
        }
        """

        let decoded = try JSONDecoder().decode(RecommendationResponse.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.recommendedMeal.title, "Salmon Rice Bowl")
        XCTAssertEqual(decoded.nearbyOptions.count, 1)
        XCTAssertEqual(decoded.nearbyOptions.first?.distanceMiles, 1.2)
    }

    func testStreakIgnoresEmptyTodayWhenYesterdayHasMeal() {
        let today = Date().startOfDay
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)?.startOfDay ?? today

        let yesterdaySummary = DailySummary(date: yesterday, mealCount: 1)
        let summaries: [Date: DailySummary] = [
            yesterday: yesterdaySummary
        ]

        let streak = StreakCalculator.currentStreak(summariesByDay: summaries, today: today)
        XCTAssertEqual(streak, 1)
    }

    func testStreakCountsTodayAndYesterdayWhenBothHaveMeal() {
        let today = Date().startOfDay
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)?.startOfDay ?? today

        let todaySummary = DailySummary(date: today, mealCount: 1)
        let yesterdaySummary = DailySummary(date: yesterday, mealCount: 1)
        let summaries: [Date: DailySummary] = [
            today: todaySummary,
            yesterday: yesterdaySummary
        ]

        let streak = StreakCalculator.currentStreak(summariesByDay: summaries, today: today)
        XCTAssertEqual(streak, 2)
    }

    func testQwenAnalyzeMealUsesChatCompletionsPayload() async throws {
        let imageDataURL = "data:image/jpeg;base64,AAA"
        let responseObject: [String: Any] = [
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": """
                        {"foods":[{"name":"Noodles","portion":"1 bowl","confidence":0.88}],"calories_estimate":520,"macros_estimate":{"protein_g":18,"carbs_g":74,"fat_g":16},"diet_flags":["high_sodium"],"allergen_warnings":["gluten"],"notes":"Estimated from visible portion."}
                        """
                    ],
                    "finish_reason": "stop"
                ]
            ]
        ]

        MockURLProtocol.setRequestHandler { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try self.jsonData(responseObject))
        }

        let client = makeLLMClient(provider: .qwen)
        let result = try await client.analyzeMeal(imageDataURL: imageDataURL)

        XCTAssertEqual(result.foods.first?.name, "Noodles")
        XCTAssertEqual(result.caloriesEstimate, 520)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest())
        XCTAssertEqual(request.url?.absoluteString, "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")

        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(payload["input"])
        XCTAssertEqual(payload["enable_thinking"] as? Bool, false)
        XCTAssertEqual(payload["model"] as? String, "qwen3.5-plus")

        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue((messages[0]["content"] as? String)?.contains("JSON schema:") == true)

        let userContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        let imagePart = try XCTUnwrap(userContent.first)
        let imagePayload = try XCTUnwrap(imagePart["image_url"] as? [String: Any])
        XCTAssertEqual(imagePart["type"] as? String, "image_url")
        XCTAssertEqual(imagePayload["url"] as? String, imageDataURL)
        XCTAssertEqual(userContent.last?["type"] as? String, "text")
    }

    func testOpenAIAnalyzeMealSupportsTextOnlyInput() async throws {
        let responseObject: [String: Any] = [
            "output_text": #"{"foods":[{"name":"Chicken salad","portion":"1 bowl","confidence":0.82}],"calories_estimate":430,"macros_estimate":{"protein_g":32,"carbs_g":18,"fat_g":24},"diet_flags":["high_protein"],"allergen_warnings":[],"notes":"Estimated from text description."}"#
        ]

        MockURLProtocol.setRequestHandler { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try self.jsonData(responseObject))
        }

        let client = makeLLMClient(provider: .openAI)
        let result = try await client.analyzeMeal(
            mealDescription: "Chicken salad with avocado and olive oil dressing"
        )

        XCTAssertEqual(result.foods.first?.name, "Chicken salad")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest())
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")

        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try XCTUnwrap(payload["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content.first?["type"] as? String, "input_text")
        XCTAssertTrue((content.first?["text"] as? String)?.contains("Meal description: Chicken salad with avocado and olive oil dressing") == true)
    }

    func testQwenAnalyzeMealSupportsTextOnlyInput() async throws {
        let responseObject: [String: Any] = [
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": """
                        {"foods":[{"name":"Soup noodles","portion":"1 bowl","confidence":0.8}],"calories_estimate":500,"macros_estimate":{"protein_g":20,"carbs_g":70,"fat_g":14},"diet_flags":[],"allergen_warnings":["gluten"],"notes":"Estimated from text description."}
                        """
                    ],
                    "finish_reason": "stop"
                ]
            ]
        ]

        MockURLProtocol.setRequestHandler { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try self.jsonData(responseObject))
        }

        let client = makeLLMClient(provider: .qwen)
        let result = try await client.analyzeMeal(
            mealDescription: "A large bowl of beef noodles with soup and scallions"
        )

        XCTAssertEqual(result.foods.first?.name, "Soup noodles")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest())
        XCTAssertEqual(request.url?.absoluteString, "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")

        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertNotNil(messages[1]["content"] as? String)
        XCTAssertTrue((messages[1]["content"] as? String)?.contains("Meal description: A large bowl of beef noodles with soup and scallions") == true)
    }

    func testOpenAITranscribeMedicalUsesCombinedImageInputs() async throws {
        let responseObject: [String: Any] = [
            "output_text": #"{"raw_text":"Page 1\nPage 2"}"#
        ]

        MockURLProtocol.setRequestHandler { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try self.jsonData(responseObject))
        }

        let client = makeLLMClient(provider: .openAI)
        let result = try await client.transcribeMedical(
            imageDataURLs: [
                "data:image/jpeg;base64,AAA",
                "data:image/jpeg;base64,BBB"
            ]
        )

        XCTAssertEqual(result.rawText, "Page 1\nPage 2")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest())
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")

        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try XCTUnwrap(payload["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])

        XCTAssertEqual(content.count, 3)
        XCTAssertEqual(content.first?["type"] as? String, "input_text")
        XCTAssertEqual(content[1]["type"] as? String, "input_image")
        XCTAssertEqual(content[1]["image_url"] as? String, "data:image/jpeg;base64,AAA")
        XCTAssertEqual(content[2]["type"] as? String, "input_image")
        XCTAssertEqual(content[2]["image_url"] as? String, "data:image/jpeg;base64,BBB")
    }

    func testQwenTranscribeMedicalUsesCombinedImageInputs() async throws {
        let responseObject: [String: Any] = [
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": [
                            [
                                "type": "text",
                                "text": """
                                ```json
                                {"raw_text":"CBC normal"}
                                ```
                                """
                            ]
                        ]
                    ],
                    "finish_reason": "stop"
                ]
            ]
        ]

        MockURLProtocol.setRequestHandler { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try self.jsonData(responseObject))
        }

        let client = makeLLMClient(provider: .qwen)
        let result = try await client.transcribeMedical(
            imageDataURLs: [
                "data:image/jpeg;base64,BBB",
                "data:image/jpeg;base64,CCC"
            ]
        )

        XCTAssertEqual(result.rawText, "CBC normal")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest())
        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "qwen3.5-plus")

        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        let userContent = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(userContent.count, 3)
        XCTAssertEqual(userContent[0]["type"] as? String, "image_url")
        XCTAssertEqual((userContent[0]["image_url"] as? [String: Any])?["url"] as? String, "data:image/jpeg;base64,BBB")
        XCTAssertEqual(userContent[1]["type"] as? String, "image_url")
        XCTAssertEqual((userContent[1]["image_url"] as? [String: Any])?["url"] as? String, "data:image/jpeg;base64,CCC")
        XCTAssertEqual(userContent[2]["type"] as? String, "text")
    }

    func testQwenRecommendationUsesPlainChatMessages() async throws {
        let responseObject: [String: Any] = [
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": """
                        {"recommended_meal":{"title":"Chicken Rice","why":"Balanced protein and carbs for lunch.","nutrition_focus":["protein","balanced_energy"],"suggested_ingredients":["chicken","rice","greens"],"estimated_macros":{"protein_g":35,"carbs_g":58,"fat_g":14},"estimated_calories":510},"nearby_options":[{"name":"Green Bowl","reason":"Lean protein nearby","distance_miles":0.8}]}
                        """
                    ],
                    "finish_reason": "stop"
                ]
            ]
        ]

        MockURLProtocol.setRequestHandler { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try self.jsonData(responseObject))
        }

        let client = makeLLMClient(provider: .qwen)
        let result = try await client.recommendNextMeal(context: makeRecommendationContext())

        XCTAssertEqual(result.recommendedMeal.title, "Chicken Rice")
        XCTAssertEqual(result.nearbyOptions.first?.name, "Green Bowl")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest())
        XCTAssertEqual(request.url?.absoluteString, "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")

        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "qwen3.5-plus")

        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue((messages[0]["content"] as? String)?.contains("JSON schema:") == true)
        XCTAssertNotNil(messages[1]["content"] as? String)
        XCTAssertNil(messages[1]["content"] as? [[String: Any]])
    }

    private func makeImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeRecommendationContext() -> RecommendationContext {
        RecommendationContext(
            generatedAt: Date(timeIntervalSince1970: 1_730_000_000),
            currentLocalTime: CurrentTimeContext(
                localDateTime: "2026-03-03T12:30:00",
                timezoneIdentifier: "Asia/Shanghai",
                timezoneOffsetMinutes: 480,
                inferredMealType: .lunch
            ),
            todayIntake: TodayIntakeContext(
                mealCount: 1,
                totalCalories: 620
            ),
            healthSnapshot: nil,
            recentMeals: [
                RecentMealContext(
                    date: Date(timeIntervalSince1970: 1_729_996_400),
                    mealType: .breakfast,
                    calories: 620,
                    macros: MacroEstimate(proteinG: 24, carbsG: 70, fatG: 18),
                    notes: "Oatmeal and eggs"
                )
            ],
            nearbyRestaurants: [
                NearbyRestaurantContext(
                    name: "Green Bowl",
                    distanceMiles: 0.8,
                    category: "Healthy"
                )
            ],
            preferences: UserPreferencesPayload(
                dietStyle: .omnivore,
                dietTarget: .maintainHealth,
                allergies: [],
                favoriteCuisines: ["Chinese"],
                dislikes: ["cilantro"],
                budgetLevel: .medium,
                radiusMiles: 2
            )
        )
    }

    private func makeLLMClient(provider: LLMProvider) -> LLMClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]

        return LLMClient(
            session: URLSession(configuration: configuration),
            responseLanguageProvider: { .english },
            configurationProvider: {
                LLMRequestConfiguration(
                    provider: provider,
                    qwenRegion: provider == .qwen ? .beijing : nil
                )
            },
            keyProvider: { _ in "test-key" }
        )
    }

    private func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }
}
