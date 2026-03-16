import Foundation

enum LLMClientError: LocalizedError {
    case missingAPIKey
    case invalidRequest
    case cancelled
    case httpError(code: Int, message: String)
    case emptyOutput
    case invalidJSON(message: String)
    case decodingError(String)
    case transportError(String)

    var errorDescription: String? {
        switch AppLanguage.current {
        case .english:
            switch self {
            case .missingAPIKey:
                return "Please set your API key (OpenAI or Qwen) in onboarding/settings."
            case .invalidRequest:
                return "Unable to prepare request to the model provider."
            case .cancelled:
                return "The request was cancelled."
            case .httpError(_, let message):
                return message
            case .emptyOutput:
                return "No result was returned. Please retry."
            case .invalidJSON(let message):
                return message
            case .decodingError(let message):
                return "Unable to decode model response: \(message)"
            case .transportError(let message):
                return message
            }
        case .simplifiedChinese:
            switch self {
            case .missingAPIKey:
                return "请先在引导或设置中配置 API Key（OpenAI 或 Qwen）。"
            case .invalidRequest:
                return "无法构建模型提供方请求。"
            case .cancelled:
                return "请求已取消。"
            case .httpError(_, let message):
                return message
            case .emptyOutput:
                return "未返回结果，请重试。"
            case .invalidJSON(let message):
                return message
            case .decodingError(let message):
                return "无法解析模型返回：\(message)"
            case .transportError(let message):
                return message
            }
        }
    }
}

actor LLMClient {
    private static let openAIRequestTimeout: TimeInterval = 45
    private static let qwenRequestTimeout: TimeInterval = 120

    private enum RequestContent {
        case text(String)
        case imagePrompt(text: String, imageDataURLs: [String])
    }

    private let session: URLSession
    private let responseLanguageProvider: @Sendable () -> AppLanguage
    private let configurationProvider: @Sendable () -> LLMRequestConfiguration
    private let keyProvider: @Sendable (LLMRequestConfiguration) throws -> String
    private let openAIModel: String
    private let qwenModel: String

    init(
        openAIModel: String = LLMSettings.openAIDefaultModel,
        qwenModel: String = LLMSettings.qwenDefaultModel,
        session: URLSession? = nil,
        responseLanguageProvider: @escaping @Sendable () -> AppLanguage = { .english },
        configurationProvider: @escaping @Sendable () -> LLMRequestConfiguration,
        keyProvider: @escaping @Sendable (LLMRequestConfiguration) throws -> String
    ) {
        self.openAIModel = openAIModel
        self.qwenModel = qwenModel
        self.responseLanguageProvider = responseLanguageProvider
        self.configurationProvider = configurationProvider
        self.keyProvider = keyProvider

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = Self.qwenRequestTimeout
            configuration.timeoutIntervalForResource = Self.qwenRequestTimeout
            self.session = URLSession(configuration: configuration)
        }
    }

    func analyzeMeal(
        imageDataURL: String? = nil,
        mealDescription: String? = nil,
        consumptionShare: Double = 1.0,
        extraContext: String? = nil,
        dietTarget: DietTarget = .maintainHealth
    ) async throws -> MealAnalysis {
        let trimmedImageDataURL = imageDataURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validImageDataURL = (trimmedImageDataURL?.isEmpty == false) ? trimmedImageDataURL : nil
        let trimmedMealDescription = mealDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let boundedMealDescription = String(trimmedMealDescription.prefix(400))
        let clampedShare = max(0.1, min(1.0, consumptionShare))
        let consumedPercent = Int((clampedShare * 100).rounded())
        let consumedTenths = Int((clampedShare * 10).rounded())
        let trimmedContext = extraContext?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let boundedContext = String(trimmedContext.prefix(400))
        guard validImageDataURL != nil || !boundedMealDescription.isEmpty || !boundedContext.isEmpty else {
            throw LLMClientError.invalidRequest
        }

        let languageDirective = responseLanguageProvider().openAIResponseLanguageDirective
        let instructions = """
        You are a nutrition analyst. Identify foods from the provided meal photo and/or user description, estimate portions, calories, and macros. Be concise.
        The user will provide a consumed share value that indicates what fraction of the described or visible meal was actually eaten.
        You MUST estimate calories and macros for the consumed portion only, not the full plate.
        Apply the user's diet target when deciding recommendations and note tone: \(dietTarget.aiGuidance)
        Return ONLY JSON that matches the schema.
        \(languageDirective)
        """

        var mealContextText = """
        Analyze this meal for nutritional and calorie information.
        User diet target: \(dietTarget.rawValue).
        Consumed share: \(consumedTenths)/10 (\(consumedPercent)%).
        Base your estimates on the consumed share.
        """
        if !boundedMealDescription.isEmpty {
            mealContextText += "\nMeal description: \(boundedMealDescription)"
        }
        if !boundedContext.isEmpty {
            mealContextText += "\nAdditional user context: \(boundedContext)"
        }

        let requestContent: RequestContent
        if let validImageDataURL {
            requestContent = .imagePrompt(text: mealContextText, imageDataURLs: [validImageDataURL])
        } else {
            requestContent = .text(mealContextText)
        }

        return try await decodeStructured(
            schemaName: "meal_analysis",
            schema: JSONSchemas.mealAnalysis,
            instructions: instructions,
            content: requestContent,
            responseType: MealAnalysis.self
        )
    }

    func transcribeMedical(imageDataURL: String) async throws -> MedicalTranscript {
        try await transcribeMedical(imageDataURLs: [imageDataURL])
    }

    func transcribeMedical(imageDataURLs: [String]) async throws -> MedicalTranscript {
        let validImageDataURLs = imageDataURLs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !validImageDataURLs.isEmpty else {
            throw LLMClientError.invalidRequest
        }

        let instructions = """
        Transcribe all text from the provided medical report images. Return only JSON with a single key raw_text containing the full transcript. No explanation.
        Preserve original text exactly as it appears in the image without translating.
        If multiple images are provided, combine the transcript into one continuous raw_text in image order.
        """

        return try await decodeStructured(
            schemaName: "medical_transcript",
            schema: JSONSchemas.medicalTranscript,
            instructions: instructions,
            content: .imagePrompt(
                text: "Extract text from these medical record images in order and combine them into one transcript.",
                imageDataURLs: validImageDataURLs
            ),
            responseType: MedicalTranscript.self
        )
    }

    func recommendNextMeal(context: RecommendationContext) async throws -> RecommendationResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let contextData = try encoder.encode(context)
        let contextJSON = String(data: contextData, encoding: .utf8) ?? "{}"
        let languageDirective = responseLanguageProvider().openAIResponseLanguageDirective

        let instructions = """
        You are a meal recommendation engine. Using the provided context, produce exactly ONE recommendation. If nearby restaurant candidates exist, pick at most 3 options. Return only JSON per schema. Keep rationale short.
        Use context.current_local_time.local_date_time and context.current_local_time.inferred_meal_type to align the recommendation with breakfast/lunch/dinner timing.
        Use context.today_intake.total_calories (or context.todayIntake.totalCalories) as the explicit total intake for TODAY so far.
        Use context.today_intake.meal_count (or context.todayIntake.mealCount) to judge how complete today's intake log is.
        If context.health_snapshot.workouts (or context.healthSnapshot.workouts) exists, use workout type, duration, and calories to adjust recovery-focused meal suggestions.
        Prioritize context.preferences.dietTarget (or context.preferences.diet_target). If the target is lose_weight, guide toward an overall 200-300 kcal daily deficit while considering today's total intake, activity, age, body weight, and recent meals.
        \(languageDirective)
        """

        var result: RecommendationResponse = try await decodeStructured(
            schemaName: "next_meal_recommendation",
            schema: JSONSchemas.recommendation,
            instructions: instructions,
            content: .text("Recommendation context JSON:\n\(contextJSON)"),
            responseType: RecommendationResponse.self
        )

        if result.nearbyOptions.count > 3 {
            result = RecommendationResponse(
                recommendedMeal: result.recommendedMeal,
                nearbyOptions: Array(result.nearbyOptions.prefix(3))
            )
        }

        return result
    }

    private func decodeStructured<T: Decodable>(
        schemaName: String,
        schema: [String: Any],
        instructions: String,
        content: RequestContent,
        responseType: T.Type
    ) async throws -> T {
        let responseText = try await structuredRequest(
            schemaName: schemaName,
            schema: schema,
            instructions: instructions,
            content: content
        )

        guard let data = responseText.data(using: .utf8) else {
            throw LLMClientError.invalidJSON(
                message: LocalizedText.ui("Model output was not UTF-8 JSON.", "模型输出不是有效的 UTF-8 JSON。")
            )
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LLMClientError.decodingError(error.localizedDescription)
        }
    }

    private func structuredRequest(
        schemaName: String,
        schema: [String: Any],
        instructions: String,
        content: RequestContent
    ) async throws -> String {
        let configuration = configurationProvider()

        switch configuration.provider {
        case .openAI:
            return try await structuredRequestOpenAI(
                configuration: configuration,
                schemaName: schemaName,
                schema: schema,
                instructions: instructions,
                content: content
            )
        case .qwen:
            return try await structuredRequestQwen(
                configuration: configuration,
                schema: schema,
                instructions: instructions,
                content: content
            )
        }
    }

    private func structuredRequestOpenAI(
        configuration: LLMRequestConfiguration,
        schemaName: String,
        schema: [String: Any],
        instructions: String,
        content: RequestContent
    ) async throws -> String {
        do {
            let data = try await sendOpenAIRequest(
                configuration: configuration,
                schemaName: schemaName,
                schema: schema,
                instructions: instructions,
                content: content,
                strict: true
            )
            return try extractValidatedJSONText(from: data)
        } catch let error as LLMClientError {
            if case .httpError(let code, _) = error, code == 400 {
                let data = try await sendOpenAIRequest(
                    configuration: configuration,
                    schemaName: schemaName,
                    schema: schema,
                    instructions: instructions,
                    content: content,
                    strict: false
                )
                return try extractValidatedJSONText(from: data)
            }
            throw error
        }
    }

    private func structuredRequestQwen(
        configuration: LLMRequestConfiguration,
        schema: [String: Any],
        instructions: String,
        content: RequestContent
    ) async throws -> String {
        let firstResponse = try await sendQwenRequest(
            configuration: configuration,
            schema: schema,
            instructions: instructions,
            content: content,
            strictJSONRetry: false
        )

        if let extracted = try? extractValidatedQwenJSON(from: firstResponse) {
            return extracted
        }

        let secondResponse = try await sendQwenRequest(
            configuration: configuration,
            schema: schema,
            instructions: instructions,
            content: content,
            strictJSONRetry: true
        )
        return try extractValidatedQwenJSON(from: secondResponse)
    }

    private func sendOpenAIRequest(
        configuration: LLMRequestConfiguration,
        schemaName: String,
        schema: [String: Any],
        instructions: String,
        content: RequestContent,
        strict: Bool
    ) async throws -> Data {
        var format: [String: Any] = [
            "type": "json_schema",
            "name": schemaName,
            "schema": schema
        ]
        if strict {
            format["strict"] = true
        }

        let payload: [String: Any] = [
            "model": model(for: configuration),
            "instructions": instructions,
            "input": [
                [
                    "role": "user",
                    "content": buildOpenAIContent(for: content)
                ]
            ],
            "text": [
                "format": format
            ]
        ]

        return try await performRequest(configuration: configuration, payload: payload)
    }

    private func sendQwenRequest(
        configuration: LLMRequestConfiguration,
        schema: [String: Any],
        instructions: String,
        content: RequestContent,
        strictJSONRetry: Bool
    ) async throws -> Data {
        let payload: [String: Any] = [
            "model": model(for: configuration),
            "messages": buildQwenMessages(
                instructions: instructions,
                schema: schema,
                content: content,
                strictJSONRetry: strictJSONRetry
            ),
            "enable_thinking": false
        ]

        return try await performRequest(configuration: configuration, payload: payload)
    }

    private func performRequest(
        configuration: LLMRequestConfiguration,
        payload: [String: Any]
    ) async throws -> Data {
        try Task.checkCancellation()

        let apiKey = try keyProvider(configuration).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw LLMClientError.missingAPIKey
        }

        guard JSONSerialization.isValidJSONObject(payload) else {
            throw LLMClientError.invalidRequest
        }

        let endpoint = configuration.responsesEndpoint
        debugLog(
            "[LLM] route provider=\(configuration.provider.rawValue) region=\(configuration.keychainRegion?.rawValue ?? "none") model=\(model(for: configuration)) host=\(endpoint.host ?? endpoint.absoluteString)"
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = requestTimeout(for: configuration)
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw LLMClientError.cancelled
        } catch {
            throw LLMClientError.transportError(error.localizedDescription)
        }

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.transportError(LocalizedText.ui("Invalid server response.", "无效的服务器响应。"))
        }

        debugLog(
            "[LLM] status provider=\(configuration.provider.rawValue) region=\(configuration.keychainRegion?.rawValue ?? "none") host=\(endpoint.host ?? endpoint.absoluteString) status=\(httpResponse.statusCode)"
        )

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = parseHTTPErrorMessage(from: data)
                ?? LocalizedText.ui("Request failed with status \(httpResponse.statusCode).", "请求失败，状态码 \(httpResponse.statusCode)。")
            throw LLMClientError.httpError(code: httpResponse.statusCode, message: message)
        }

        return data
    }

    private func model(for configuration: LLMRequestConfiguration) -> String {
        switch configuration.provider {
        case .openAI:
            return openAIModel
        case .qwen:
            return qwenModel
        }
    }

    private func requestTimeout(for configuration: LLMRequestConfiguration) -> TimeInterval {
        switch configuration.provider {
        case .openAI:
            return Self.openAIRequestTimeout
        case .qwen:
            return Self.qwenRequestTimeout
        }
    }

    private func buildOpenAIContent(for content: RequestContent) -> [[String: Any]] {
        switch content {
        case .text(let text):
            return [["type": "input_text", "text": text]]
        case .imagePrompt(let text, let imageDataURLs):
            var builtContent: [[String: Any]] = [
                ["type": "input_text", "text": text]
            ]
            builtContent.append(
                contentsOf: imageDataURLs.map { imageDataURL in
                    ["type": "input_image", "image_url": imageDataURL]
                }
            )
            return builtContent
        }
    }

    private func buildQwenMessages(
        instructions: String,
        schema: [String: Any],
        content: RequestContent,
        strictJSONRetry: Bool
    ) -> [[String: Any]] {
        let schemaText = stringifyJSONObject(schema) ?? "{}"
        let systemPrompt: String
        if strictJSONRetry {
            systemPrompt = """
            \(instructions)
            Return ONLY valid JSON that matches the schema exactly.
            Do not include markdown, code fences, comments, or explanatory text.
            Include every required key in the schema.
            If a value is uncertain, provide the best estimate while keeping the JSON valid.
            JSON schema:
            \(schemaText)
            """
        } else {
            systemPrompt = """
            \(instructions)
            Return ONLY valid JSON that matches the schema exactly.
            Do not include markdown or any extra prose.
            JSON schema:
            \(schemaText)
            """
        }

        let userContent: Any
        switch content {
        case .text(let text):
            userContent = text
        case .imagePrompt(let text, let imageDataURLs):
            var contentParts = imageDataURLs.map { imageDataURL in
                [
                    "type": "image_url",
                    "image_url": [
                        "url": imageDataURL
                    ]
                ]
            }
            contentParts.append(["type": "text", "text": text])
            userContent = contentParts
        }

        return [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userContent]
        ]
    }

    private func extractValidatedJSONText(from data: Data) throws -> String {
        let extracted = try extractOutputText(from: data)
        let cleaned = JSONValidation.cleanedJSONString(extracted)

        guard JSONValidation.isValidJSON(string: cleaned) else {
            throw LLMClientError.invalidJSON(
                message: LocalizedText.ui("Model output was not valid JSON. Please retry.", "模型返回的 JSON 无效，请重试。")
            )
        }

        return cleaned
    }

    private func extractValidatedQwenJSON(from data: Data) throws -> String {
        if let functionCallArguments = try extractFunctionCallArguments(from: data) {
            let cleaned = JSONValidation.cleanedJSONString(functionCallArguments)
            guard JSONValidation.isValidJSON(string: cleaned) else {
                throw LLMClientError.invalidJSON(
                    message: LocalizedText.ui("Function-call arguments were not valid JSON. Please retry.", "函数调用参数不是有效 JSON，请重试。")
                )
            }
            return cleaned
        }

        return try extractValidatedJSONText(from: data)
    }

    private func extractFunctionCallArguments(from data: Data) throws -> String? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMClientError.emptyOutput
        }

        func argumentsString(from item: [String: Any]) -> String? {
            if (item["type"] as? String) == "function_call" {
                if let arguments = item["arguments"] as? String {
                    return arguments
                }
                if let arguments = item["arguments"], let stringified = stringifyJSONObject(arguments) {
                    return stringified
                }
            }

            if let content = item["content"] as? [[String: Any]] {
                for part in content {
                    if let arguments = argumentsString(from: part) {
                        return arguments
                    }
                }
            }

            return nil
        }

        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                if let arguments = argumentsString(from: item) {
                    return arguments
                }
            }
        }

        if let choices = json["choices"] as? [[String: Any]] {
            for choice in choices {
                if let message = choice["message"] as? [String: Any] {
                    if let toolCalls = message["tool_calls"] as? [[String: Any]] {
                        for toolCall in toolCalls {
                            if let function = toolCall["function"] as? [String: Any] {
                                if let arguments = function["arguments"] as? String {
                                    return arguments
                                }
                                if let arguments = function["arguments"],
                                   let stringified = stringifyJSONObject(arguments) {
                                    return stringified
                                }
                            }
                        }
                    }

                    if let arguments = argumentsString(from: message) {
                        return arguments
                    }
                }
            }
        }

        return nil
    }

    private func parseHTTPErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let errorObj = json["error"] as? [String: Any],
            let message = errorObj["message"] as? String
        else {
            return nil
        }
        return message
    }

    private func extractOutputText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMClientError.emptyOutput
        }

        if let outputText = json["output_text"] as? String,
           !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText
        }

        var segments: [String] = []

        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                if let itemText = item["text"] as? String {
                    segments.append(itemText)
                }

                if let content = item["content"] as? [[String: Any]] {
                    for part in content {
                        if let text = part["text"] as? String {
                            segments.append(text)
                        }

                        if let jsonPart = part["json"],
                           let stringified = stringifyJSONObject(jsonPart) {
                            segments.append(stringified)
                        }
                    }
                }
            }
        }

        if let choices = json["choices"] as? [[String: Any]] {
            for choice in choices {
                if let message = choice["message"] as? [String: Any] {
                    if let content = message["content"] as? String {
                        segments.append(content)
                    }

                    if let contentParts = message["content"] as? [[String: Any]] {
                        for part in contentParts {
                            if let text = part["text"] as? String {
                                segments.append(text)
                            }

                            if let jsonPart = part["json"],
                               let stringified = stringifyJSONObject(jsonPart) {
                                segments.append(stringified)
                            }
                        }
                    }
                }
            }
        }

        let merged = segments
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !merged.isEmpty else {
            throw LLMClientError.emptyOutput
        }

        return merged
    }

    private func stringifyJSONObject(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        guard
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return text
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: LLMSettings.debugLoggingStorageKey) else { return }
        print(message())
    }
}
