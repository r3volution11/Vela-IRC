// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import VelaFoundation
import VelaStore
@testable import VelaIntelligence

private typealias F = ProviderFixtures

// MARK: - Anthropic

@Suite("Anthropic Messages API")
struct AnthropicAPITests {
    func api(_ server: StubServer, waits: WaitRecorder = WaitRecorder()) -> AnthropicAPI {
        AnthropicAPI(identity: F.identity, client: F.client(waits), key: "sk-ant-test", baseURL: server.baseURL)
    }

    @Test func requestShape() async throws {
        let server = StubServer([F.anthropicEvents(["Hi"])])
        _ = await F.collect(api(server), F.call("claude-opus-5-5", instructions: "Rules.", prompt: "[1] alice: hi", limit: 500))
        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.path() == "/v1/messages")
        #expect(request.header("x-api-key") == "sk-ant-test")
        #expect(request.header("anthropic-version") == "2026-10-21")
        #expect(request.header("Content-Type") == "application/json")
        let body = try #require(request.json)
        #expect(body["model"]?.stringValue == "claude-opus-5-5")
        #expect(body["system"]?.stringValue == "Rules.")
        #expect(body["stream"]?.boolValue == true)
        // Room for thinking on top of the reply.
        #expect(body["max_tokens"]?.intValue == 500 + AIModelCall.thinkingAllowance)
        #expect(body["output_config"]?["effort"]?.stringValue == "low")
        let messages = try #require(body["messages"]?.arrayValue)
        #expect(messages.count == 1)
        #expect(messages[0]["role"]?.stringValue == "user")
        #expect(messages[0]["content"]?.stringValue == "[1] alice: hi")
        // This API version rejects sampling parameters, and nothing is prefilled.
        #expect(body["temperature"] == nil)
        #expect(body["top_p"] == nil)
        #expect(body["thinking"] == nil)
        #expect(!request.url.absoluteString.contains("sk-ant-test"))
    }

    @Test func noEffortForAModelThatDoesntTakeOne() async throws {
        let server = StubServer([F.anthropicEvents(["Hi"])])
        _ = await F.collect(api(server), F.call("claude-haiku-4-5", thinking: nil))
        #expect(try #require(server.requests.first?.json)["output_config"] == nil)
    }

    @Test func streamsTextAndSkipsThinking() async throws {
        let server = StubServer([F.anthropicEvents(["OVERVIEW: ", "Release ", "talk."])])
        let text = try await F.collect(api(server), F.call("claude-opus-5-5")).get()
        #expect(text == "OVERVIEW: Release talk.")
        #expect(!text.contains("secret"))
    }

    @Test func refusalIsADecline() async {
        let server = StubServer([F.anthropicEvents(["I can"], stopReason: "refusal")])
        let result = await F.collect(api(server), F.call("claude-opus-5-5"))
        #expect(throws: CatchUpModelError.declined) { try result.get() }
    }

    @Test func errorEventMidStream() async {
        let server = StubServer([.events([
            #"{"type":"message_start","message":{"id":"m"}}"#,
            #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
        ])])
        let result = await F.collect(api(server), F.call("claude-opus-5-5"))
        #expect(F.reason(result.failureValue) == .overloaded)
    }

    @Test func badKey() async {
        let server = StubServer([.json(401, #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)])
        let result = await F.collect(api(server), F.call("claude-opus-5-5"))
        #expect(F.reason(result.failureValue) == .badKey)
        #expect(server.requests.count == 1)
    }

    @Test func promptTooLongIsContextExceeded() async {
        let server = StubServer([.json(400, #"{"type":"error","error":{"type":"invalid_request_error","message":"prompt is too long: 1200000 tokens > 1000000 maximum"}}"#)])
        let result = await F.collect(api(server), F.call("claude-opus-5-5"))
        #expect(throws: CatchUpModelError.contextExceeded) { try result.get() }
    }

    @Test func rateLimitWaitsAsAskedThenSucceeds() async throws {
        let waits = WaitRecorder()
        let server = StubServer([
            .json(429, #"{"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}"#, headers: ["retry-after": "3"]),
            F.anthropicEvents(["Done."]),
        ])
        let text = try await F.collect(api(server, waits: waits), F.call("claude-opus-5-5")).get()
        #expect(text == "Done.")
        #expect(server.requests.count == 2)
        #expect(waits.recorded == [.seconds(3)])
    }

    @Test func overloadedIsRetriedWithBackoffThenReported() async {
        let waits = WaitRecorder()
        let server = StubServer([.json(529, #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)])
        let result = await F.collect(api(server, waits: waits), F.call("claude-opus-5-5"))
        #expect(F.reason(result.failureValue) == .overloaded)
        #expect(server.requests.count == 3)
        #expect(waits.recorded == [.seconds(1), .seconds(2)])
    }

    @Test func aWaitLongerThanTheLimitIsntWaitedFor() async {
        let waits = WaitRecorder()
        let server = StubServer([.json(429, #"{"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}"#, headers: ["retry-after": "120"])])
        let result = await F.collect(api(server, waits: waits), F.call("claude-opus-5-5"))
        #expect(F.reason(result.failureValue) == .rateLimited)
        #expect(server.requests.count == 1)
        #expect(waits.recorded.isEmpty)
    }

    @Test func spendCapIsQuotaAndNotRetried() async {
        let server = StubServer([.json(429, #"{"type":"error","error":{"type":"rate_limit_error","message":"cap","details":{"error_code":"enforced_spend_limit_reached"}}}"#)])
        let result = await F.collect(api(server), F.call("claude-opus-5-5"))
        #expect(F.reason(result.failureValue) == .quota)
        #expect(server.requests.count == 1)
    }

    @Test func modelListPagesAndPutsTheRecommendedFirst() async throws {
        let server = StubServer([
            .json(200, #"""
            {"data":[
              {"type":"model","id":"claude-haiku-4-5","display_name":"Claude Haiku 4.5","max_input_tokens":200000,
               "capabilities":{"effort":{"supported":false}}},
              {"type":"model","id":"claude-sonnet-5-5","display_name":"Claude Sonnet 5.5","max_input_tokens":1000000,
               "capabilities":{"effort":{"supported":true,"low":{"supported":true}}}}
            ],"has_more":true,"last_id":"claude-sonnet-5-5"}
            """#),
            .json(200, #"""
            {"data":[{"type":"model","id":"claude-opus-5-5","display_name":"Claude Opus 5.5","max_input_tokens":1000000,
              "capabilities":{"effort":{"supported":true,"low":{"supported":true}}}}],"has_more":false}
            """#),
        ])
        let models = try await api(server).listModels()
        #expect(models.map(\.id) == ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5"])
        #expect(models[0].isRecommended)
        #expect(!models[1].isRecommended)
        #expect(models[0].name == "Claude Opus 5.5")
        #expect(models[2].contextTokens == 200_000)
        #expect(models[2].thinkingControl == false)
        #expect(models[1].thinkingControl == true)
        let pages = server.requests
        #expect(pages.count == 2)
        #expect(pages[0].method == "GET")
        #expect(pages[0].header("x-api-key") == "sk-ant-test")
        #expect(pages[1].url.query()?.contains("after_id=claude-sonnet-5-5") == true)
    }
}

// MARK: - OpenAI

@Suite("OpenAI Responses API")
struct OpenAIAPITests {
    func api(_ server: StubServer, waits: WaitRecorder = WaitRecorder()) -> OpenAIAPI {
        OpenAIAPI(identity: F.identity, client: F.client(waits), key: "sk-test", baseURL: server.baseURL)
    }

    @Test func requestShape() async throws {
        let server = StubServer([F.openAIEvents(["Hi"])])
        _ = await F.collect(api(server), F.call("gpt-6.2-sol", instructions: "Rules.", prompt: "[1] alice: hi", limit: 750))
        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.path() == "/v1/responses")
        #expect(request.header("Authorization") == "Bearer sk-test")
        let body = try #require(request.json)
        #expect(body["model"]?.stringValue == "gpt-6.2-sol")
        #expect(body["instructions"]?.stringValue == "Rules.")
        #expect(body["input"]?.stringValue == "[1] alice: hi")
        #expect(body["stream"]?.boolValue == true)
        #expect(body["store"]?.boolValue == false)
        #expect(body["max_output_tokens"]?.intValue == 750 + AIModelCall.thinkingAllowance)
        #expect(body["reasoning"]?["effort"]?.stringValue == "low")
    }

    @Test func noReasoningForOlderModels() async throws {
        let server = StubServer([F.openAIEvents(["Hi"])])
        _ = await F.collect(api(server), F.call("gpt-4o", thinking: false))
        #expect(try #require(server.requests.first?.json)["reasoning"] == nil)
    }

    @Test func streamsText() async throws {
        let server = StubServer([F.openAIEvents(["OVERVIEW: ", "Talk."])])
        #expect(try await F.collect(api(server), F.call("gpt-6.2-sol")).get() == "OVERVIEW: Talk.")
    }

    @Test func refusalIsADecline() async {
        let server = StubServer([.events([
            #"{"type":"response.created","response":{"id":"r"}}"#,
            #"{"type":"response.refusal.delta","delta":"I can't help with that."}"#,
        ])])
        let result = await F.collect(api(server), F.call("gpt-6.2-sol"))
        #expect(throws: CatchUpModelError.declined) { try result.get() }
    }

    @Test func contentFilterIsADeclineButTheOutputLimitIsntAnError() async throws {
        let filtered = StubServer([.events([
            #"{"type":"response.output_text.delta","delta":"Part"}"#,
            #"{"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"content_filter"}}}"#,
        ])])
        await #expect(throws: CatchUpModelError.declined) { try await F.collect(api(filtered), F.call("gpt-6.2-sol")).get() }
        let limited = StubServer([.events([
            #"{"type":"response.output_text.delta","delta":"Part"}"#,
            #"{"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"}}}"#,
        ])])
        #expect(try await F.collect(api(limited), F.call("gpt-6.2-sol")).get() == "Part")
    }

    @Test func failedResponse() async {
        let server = StubServer([.events([
            #"{"type":"response.failed","response":{"status":"failed","error":{"code":"server_error","message":"oops"}}}"#,
        ])])
        #expect(F.reason(await F.collect(api(server), F.call("gpt-6.2-sol")).failureValue) == .overloaded)
    }

    @Test func insufficientQuotaIsntRetried() async {
        let waits = WaitRecorder()
        let server = StubServer([.json(429, #"{"error":{"message":"You exceeded your current quota","type":"insufficient_quota","code":"insufficient_quota"}}"#)])
        let result = await F.collect(api(server, waits: waits), F.call("gpt-6.2-sol"))
        #expect(F.reason(result.failureValue) == .quota)
        #expect(server.requests.count == 1)
        #expect(waits.recorded.isEmpty)
    }

    @Test func rateLimitHonorsRetryAfterMilliseconds() async throws {
        let waits = WaitRecorder()
        let server = StubServer([
            .json(429, #"{"error":{"message":"Rate limit","type":"requests","code":"rate_limit_exceeded"}}"#, headers: ["retry-after-ms": "1500"]),
            F.openAIEvents(["Done."]),
        ])
        #expect(try await F.collect(api(server, waits: waits), F.call("gpt-6.2-sol")).get() == "Done.")
        #expect(waits.recorded == [.milliseconds(1500)])
    }

    @Test func contextLengthExceeded() async {
        let server = StubServer([.json(400, #"{"error":{"message":"This model's maximum context length is…","type":"invalid_request_error","code":"context_length_exceeded"}}"#)])
        await #expect(throws: CatchUpModelError.contextExceeded) { try await F.collect(api(server), F.call("gpt-6.2-sol")).get() }
    }

    @Test func badKeyAndMissingModel() async {
        let key = StubServer([.json(401, #"{"error":{"message":"Incorrect API key provided: sk-te***st","type":"invalid_request_error","code":"invalid_api_key"}}"#)])
        let keyResult = await F.collect(api(key), F.call("gpt-6.2-sol"))
        #expect(F.reason(keyResult.failureValue) == .badKey)
        // The provider's message (with part of the key) isn't shown.
        if case let CatchUpModelError.provider(failure)? = keyResult.failureValue {
            #expect(!failure.message.contains("sk-"))
        }
        let model = StubServer([.json(404, #"{"error":{"message":"The model `gpt-9` does not exist","type":"invalid_request_error","code":"model_not_found"}}"#)])
        #expect(F.reason(await F.collect(api(model), F.call("gpt-9")).failureValue) == .modelNotFound)
    }

    @Test func modelListKeepsTextModelsNewestFirst() async throws {
        let server = StubServer([.json(200, #"""
        {"object":"list","data":[
          {"id":"text-embedding-3-large","object":"model","created":1700000000,"owned_by":"system"},
          {"id":"gpt-4o","object":"model","created":1710000000,"owned_by":"system"},
          {"id":"gpt-6-luna","object":"model","created":1790000000,"owned_by":"system"},
          {"id":"gpt-6.2-sol","object":"model","created":1795000000,"owned_by":"system"},
          {"id":"whisper-1","object":"model","created":1690000000,"owned_by":"system"},
          {"id":"gpt-6.2-realtime","object":"model","created":1796000000,"owned_by":"system"},
          {"id":"o4-mini","object":"model","created":1750000000,"owned_by":"system"},
          {"id":"dall-e-3","object":"model","created":1698000000,"owned_by":"system"}
        ]}
        """#)])
        let models = try await api(server).listModels()
        #expect(models.map(\.id) == ["gpt-6.2-sol", "gpt-6-luna", "o4-mini", "gpt-4o"])
        #expect(models[0].isRecommended)
        #expect(models[0].name == "GPT-6.2 Sol")
        #expect(models.first { $0.id == "gpt-4o" }?.thinkingControl == false)
        #expect(models.first { $0.id == "o4-mini" }?.thinkingControl == true)
        #expect(server.requests.first?.header("Authorization") == "Bearer sk-test")
    }
}

// MARK: - Gemini

@Suite("Gemini API")
struct GeminiAPITests {
    func api(_ server: StubServer) -> GeminiAPI {
        GeminiAPI(identity: F.identity, client: F.client(), key: "AIza-test", baseURL: server.baseURL)
    }

    @Test func requestShapeKeepsTheKeyOutOfTheURL() async throws {
        let server = StubServer([F.geminiEvents(["Hi"])])
        _ = await F.collect(api(server), F.call("gemini-3.8-flash", instructions: "Rules.", prompt: "[1] alice: hi", limit: 500))
        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.url.path() == "/v1/models/gemini-3.8-flash:streamGenerateContent")
        #expect(request.url.query() == "alt=sse")
        #expect(request.header("x-goog-api-key") == "AIza-test")
        #expect(!request.url.absoluteString.contains("AIza"))
        #expect(!request.url.absoluteString.contains("key="))
        let body = try #require(request.json)
        #expect(body["systemInstruction"]?["parts"]?.arrayValue?.first?["text"]?.stringValue == "Rules.")
        let content = try #require(body["contents"]?.arrayValue?.first)
        #expect(content["role"]?.stringValue == "user")
        #expect(content["parts"]?.arrayValue?.first?["text"]?.stringValue == "[1] alice: hi")
        #expect(body["generationConfig"]?["maxOutputTokens"]?.intValue == 500 + AIModelCall.thinkingAllowance)
        #expect(body["generationConfig"]?["thinkingConfig"]?["thinkingLevel"]?.stringValue == "LOW")
    }

    @Test func streamsTextAndSkipsThoughts() async throws {
        let server = StubServer([F.geminiEvents(["OVERVIEW: ", "Talk."])])
        let text = try await F.collect(api(server), F.call("gemini-3.8-flash")).get()
        #expect(text == "OVERVIEW: Talk.")
    }

    @Test func safetyStopsAndBlockedPromptsAreDeclines() async {
        let stopped = StubServer([F.geminiEvents(["Part"], finishReason: "SAFETY")])
        await #expect(throws: CatchUpModelError.declined) { try await F.collect(api(stopped), F.call("gemini-3.8-flash")).get() }
        let blocked = StubServer([.events([#"{"promptFeedback":{"blockReason":"PROHIBITED_CONTENT"}}"#])])
        await #expect(throws: CatchUpModelError.declined) { try await F.collect(api(blocked), F.call("gemini-3.8-flash")).get() }
    }

    @Test func invalidKeyIsABadKeyEvenAsA400() async {
        let server = StubServer([.json(400, #"""
        {"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT",
          "details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"API_KEY_INVALID"}]}}
        """#)])
        #expect(F.reason(await F.collect(api(server), F.call("gemini-3.8-flash")).failureValue) == .badKey)
    }

    @Test func tooManyTokensIsContextExceeded() async {
        let server = StubServer([.json(400, #"{"error":{"code":400,"message":"The input token count (2000000) exceeds the maximum number of tokens allowed (1048576).","status":"INVALID_ARGUMENT"}}"#)])
        await #expect(throws: CatchUpModelError.contextExceeded) { try await F.collect(api(server), F.call("gemini-3.8-flash")).get() }
    }

    @Test func unavailableIsRetried() async throws {
        let server = StubServer([
            .json(503, #"{"error":{"code":503,"message":"The model is overloaded.","status":"UNAVAILABLE"}}"#),
            F.geminiEvents(["Done."]),
        ])
        #expect(try await F.collect(api(server), F.call("gemini-3.8-flash")).get() == "Done.")
        #expect(server.requests.count == 2)
    }

    @Test func modelListKeepsGeminiTextModels() async throws {
        let server = StubServer([.json(200, #"""
        {"models":[
          {"name":"models/gemini-3.5-flash-lite","displayName":"Gemini 3.5 Flash-Lite","inputTokenLimit":1048576,
           "supportedGenerationMethods":["generateContent","countTokens"],"thinking":true},
          {"name":"models/text-embedding-004","displayName":"Text Embedding","inputTokenLimit":2048,
           "supportedGenerationMethods":["embedContent"]},
          {"name":"models/gemini-3.8-flash","displayName":"Gemini 3.8 Flash","inputTokenLimit":1048576,
           "supportedGenerationMethods":["generateContent","streamGenerateContent"],"thinking":true},
          {"name":"models/gemini-2.5-flash","displayName":"Gemini 2.5 Flash","inputTokenLimit":1048576,
           "supportedGenerationMethods":["generateContent"],"thinking":true},
          {"name":"models/gemini-3.8-flash-image","displayName":"Image","supportedGenerationMethods":["generateContent"]}
        ],"nextPageToken":""}
        """#)])
        let models = try await api(server).listModels()
        #expect(models.map(\.id) == ["gemini-3.8-flash", "gemini-3.5-flash-lite", "gemini-2.5-flash"])
        #expect(models[0].isRecommended)
        #expect(models[0].contextTokens == 1_048_576)
        // Gemini 2.x takes a thinking budget, not a level.
        #expect(models[2].thinkingControl == false)
        let request = try #require(server.requests.first)
        #expect(request.header("x-goog-api-key") == "AIza-test")
        #expect(request.url.query()?.contains("key=") == false)
    }
}

// MARK: - Custom servers

@Suite("OpenAI-compatible servers")
struct OpenAICompatibleAPITests {
    func api(_ server: StubServer, key: String? = nil) -> OpenAICompatibleAPI {
        let identity = AIProviderIdentity(id: "ollama", name: "Ollama", isCustomServer: true)
        return OpenAICompatibleAPI(identity: identity, client: F.client(), key: key, baseURL: server.baseURL)
    }

    @Test func requestShape() async throws {
        let server = StubServer([F.chatEvents(["Hi"])])
        _ = await F.collect(api(server), F.call("llama3.3:70b", thinking: nil, instructions: "Rules.", prompt: "[1] alice: hi", limit: 500))
        let request = try #require(server.requests.first)
        #expect(request.url.path() == "/v1/chat/completions")
        #expect(request.header("Authorization") == nil)
        let body = try #require(request.json)
        #expect(body["model"]?.stringValue == "llama3.3:70b")
        #expect(body["stream"]?.boolValue == true)
        #expect(body["max_tokens"]?.intValue == 500 + OpenAICompatibleAPI.thinkingAllowance)
        let messages = try #require(body["messages"]?.arrayValue)
        #expect(messages.map { $0["role"]?.stringValue } == ["system", "user"])
        #expect(messages[0]["content"]?.stringValue == "Rules.")
        #expect(messages[1]["content"]?.stringValue == "[1] alice: hi")
    }

    @Test func aKeyIsSentWhenThereIsOne() async throws {
        let server = StubServer([F.chatEvents(["Hi"])])
        _ = await F.collect(api(server, key: "local-secret"), F.call("m", thinking: nil))
        #expect(server.requests.first?.header("Authorization") == "Bearer local-secret")
    }

    @Test func thinkingInTheReplyIsLeftOut() async throws {
        let server = StubServer([F.chatEvents(["<thi", "nk>Let me think", " about it.</th", "ink>\n\nOVERVIEW: ", "Talk."])])
        #expect(try await F.collect(api(server), F.call("qwen3", thinking: nil)).get() == "OVERVIEW: Talk.")
    }

    @Test func contentFilterIsADecline() async {
        let server = StubServer([F.chatEvents(["Part"], finishReason: "content_filter")])
        await #expect(throws: CatchUpModelError.declined) { try await F.collect(api(server), F.call("m", thinking: nil)).get() }
    }

    @Test func aServerThatIsntRunningCantBeReached() async {
        let server = StubServer([.fail(.cannotConnectToHost)])
        #expect(F.reason(await F.collect(api(server), F.call("m", thinking: nil)).failureValue) == .unreachable)
    }

    @Test func aModelThatIsntPulled() async {
        let server = StubServer([.json(404, #"{"error":{"message":"model \"llama9\" not found, try pulling it first","type":"api_error"}}"#)])
        #expect(F.reason(await F.collect(api(server), F.call("llama9", thinking: nil)).failureValue) == .modelNotFound)
    }

    @Test func contextOverflowInTheStream() async {
        let server = StubServer([.events([#"{"error":{"message":"the input length exceeds the context length"}}"#])])
        await #expect(throws: CatchUpModelError.contextExceeded) { try await F.collect(api(server), F.call("m", thinking: nil)).get() }
    }

    @Test func modelListLeavesOutEmbeddings() async throws {
        let server = StubServer([.json(200, #"{"object":"list","data":[{"id":"llama3.2"},{"id":"nomic-embed-text"},{"id":"qwen3:8b"}]}"#)])
        #expect(try await api(server).listModels().map(\.id) == ["llama3.2", "qwen3:8b"])
    }

    @Test func addressesAreNormalized() {
        #expect(AIProviderEntry.normalizedServerURL("localhost:11434")?.absoluteString == "http://localhost:11434/v1")
        #expect(AIProviderEntry.normalizedServerURL("http://localhost:1234/v1/")?.absoluteString == "http://localhost:1234/v1")
        #expect(AIProviderEntry.normalizedServerURL("https://gpu.example.com/api/v1")?.absoluteString == "https://gpu.example.com/api/v1")
        #expect(AIProviderEntry.normalizedServerURL("ftp://host") == nil)
        #expect(AIProviderEntry.normalizedServerURL("") == nil)
        #expect(AIServerLocation(host: "localhost") == .thisMac)
        #expect(AIServerLocation(host: "127.0.0.1") == .thisMac)
        #expect(AIServerLocation(host: "studio.local") == .localNetwork)
        #expect(AIServerLocation(host: "192.168.1.20") == .localNetwork)
        #expect(AIServerLocation(host: "172.20.0.5") == .localNetwork)
        #expect(AIServerLocation(host: "fdroid.org") == .internet)
        #expect(AIServerLocation(host: "gpu.example.com") == .internet)
    }
}

// MARK: - The model on the engine's side

@Suite("Provider models for the engine")
struct ProviderLanguageModelTests {
    @Test func digestStopsAsSoonAsItsEnough() async throws {
        let server = StubServer([F.chatEvents(["OVERVIEW: A.\n", "TOPIC: one\n", "TOPIC: two\n", "TOPIC: three\n"])])
        let api = OpenAICompatibleAPI(identity: F.identity, client: F.client(), key: nil, baseURL: server.baseURL)
        let model = ProviderLanguageModel(api: api, model: AIModelInfo(id: "m"), context: 8_192)
        let reply = try await model.digest(prompt: "p", instructions: "i", maximumResponseTokens: 500) { $0.contains("TOPIC: one\n") }
        #expect(reply == "OVERVIEW: A.\nTOPIC: one\n")
        #expect(await model.contextSize() == 8_192)
        #expect(await model.tokenCount("anything") == nil)
    }

    @Test func summarizeStreamsTheReplySoFar() async throws {
        let server = StubServer([F.chatEvents(["OVERVIEW: ", "Talk."])])
        let api = OpenAICompatibleAPI(identity: F.identity, client: F.client(), key: nil, baseURL: server.baseURL)
        let model = ProviderLanguageModel(api: api, model: AIModelInfo(id: "m"), context: 8_192)
        var snapshots: [String] = []
        for try await text in model.summarize(prompt: "p", instructions: "i", maximumResponseTokens: 500) { snapshots.append(text) }
        #expect(snapshots == ["OVERVIEW: ", "OVERVIEW: Talk."])
    }

    @Test func aReplyThatRunsOnIsCutOff() async throws {
        let long = String(repeating: "word ", count: 400)
        let server = StubServer([F.chatEvents(Array(repeating: long, count: 20))])
        let api = OpenAICompatibleAPI(identity: F.identity, client: F.client(), key: nil, baseURL: server.baseURL)
        let model = ProviderLanguageModel(api: api, model: AIModelInfo(id: "m"), context: 8_192)
        var last = ""
        for try await text in model.summarize(prompt: "p", instructions: "i", maximumResponseTokens: 200) { last = text }
        #expect(last.count < long.count * 3)
    }

    @Test func anEmptyReplyIsAFailure() async {
        let server = StubServer([F.chatEvents([])])
        let api = OpenAICompatibleAPI(identity: F.identity, client: F.client(), key: nil, baseURL: server.baseURL)
        let model = ProviderLanguageModel(api: api, model: AIModelInfo(id: "m"), context: 8_192)
        await #expect(throws: CatchUpModelError.provider(AIProviderFailure(providerID: "test", providerName: "Test Provider", reason: .emptyResponse))) {
            _ = try await model.digest(prompt: "p", instructions: "i", maximumResponseTokens: 500) { _ in false }
        }
    }

    @Test func thinkingFilter() {
        var filter = ThinkingFilter()
        #expect(filter.text(from: "Hello") == "Hello")
        #expect(filter.text(from: " <think>not this</think>") == " <think>not this</think>")
        var thinking = ThinkingFilter()
        #expect(thinking.text(from: "  <th") == "")
        #expect(thinking.text(from: "ink>hmm") == "")
        #expect(thinking.text(from: "</think>  Answer") == "Answer")
        #expect(thinking.text(from: " more") == " more")
    }

    @Test func retryAfterParsing() {
        func response(_ headers: [String: String]) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://x.test")!, statusCode: 429, httpVersion: nil, headerFields: headers)!
        }
        #expect(AIHTTPError.retryAfter(response(["retry-after": "7"])) == .seconds(7))
        #expect(AIHTTPError.retryAfter(response(["retry-after-ms": "250"])) == .milliseconds(250))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let later = "Fri, 15 Jan 2027 08:00:10 GMT"
        let date = AIHTTPError.retryAfter(response(["retry-after": later]), now: now)
        #expect(date != nil)
        #expect(AIHTTPError.retryAfter(response([:])) == nil)
    }
}

extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { error } else { nil }
    }
}
