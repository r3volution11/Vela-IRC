// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import FoundationModels
import Testing
@testable import VelaIntelligence

/// Private Cloud Compute as the router sees it, without a network: ready
/// with a fake model, or not, and timings recorded.
nonisolated final class FakeCloud: CatchUpCloud {
    let readiness: @Sendable () -> CatchUpCloudReadiness
    let onePassSeconds: Double
    let prepared = Recorder(0)
    let recorded = Recorder<[Duration]>([])
    let failures = Recorder<[CatchUpCloudFallback]>([])

    init(onePassSeconds: Double = 10, _ readiness: @escaping @Sendable () -> CatchUpCloudReadiness) {
        self.onePassSeconds = onePassSeconds
        self.readiness = readiness
    }

    convenience init(model: FakeCatchUpModel) {
        self.init { .ready(model) }
    }

    func prepare() async -> CatchUpCloudReadiness {
        prepared.update { $0 += 1 }
        return readiness()
    }

    func estimatedSeconds(passes: Int) -> Double {
        onePassSeconds * Double(passes)
    }

    func record(onePass duration: Duration) {
        recorded.update { $0.append(duration) }
    }

    func record(failure reason: CatchUpCloudFallback) {
        failures.update { $0.append(reason) }
    }
}

@Suite("Catch me up with Private Cloud Compute")
struct CatchUpRouterTests {
    typealias F = CatchUpFixtures

    /// The Mac's model: a 4,096-token context, so 240 lines of chatter
    /// take several passes.
    private func onDevice() -> FakeCatchUpModel {
        FakeCatchUpModel(context: 4096, final: { _ in [CatchUpDraft(overview: "From the Mac.")] })
    }

    /// Private Cloud Compute's model: a much larger context.
    private func cloudModel() -> FakeCatchUpModel {
        FakeCatchUpModel(context: 32_768, final: { _ in [CatchUpDraft(overview: "From the cloud.")] })
    }

    // MARK: Routing

    @Test func aShortStretchStaysOnTheMac() async throws {
        let device = onDevice()
        let remote = cloudModel()
        let cloud = FakeCloud(model: remote)
        let router = CatchUpRouter(onDevice: device, cloud: cloud)

        let summary = try await router.run(F.request(F.chatter(20)))
        #expect(summary.overview == "From the Mac.")
        #expect(summary.venue == .onDevice)
        #expect(summary.cloudFallback == nil)
        #expect(device.summarizeCalls.count == 1)
        #expect(remote.calls.value.isEmpty)
        // One pass on the Mac: Private Cloud Compute isn't even asked.
        #expect(cloud.prepared.value == 0)

        let plan = await router.plan(F.request(F.chatter(20)))
        #expect(plan == CatchUpPlan(passes: 1, transcriptTokens: plan.transcriptTokens))
        #expect(cloud.prepared.value == 0)
    }

    /// Too long for one pass on the Mac: Private Cloud Compute reads it,
    /// in one pass of its larger context.
    @Test func aLongStretchGoesToPrivateCloudCompute() async throws {
        let device = onDevice()
        let remote = cloudModel()
        let cloud = FakeCloud(model: remote)
        let router = CatchUpRouter(onDevice: device, cloud: cloud)
        let snapshots = Recorder<[CatchUpSummary]>([])

        let summary = try await router.run(F.request(F.chatter(240))) { snapshot in
            snapshots.update { $0.append(snapshot) }
        }
        #expect(summary.overview == "From the cloud.")
        #expect(summary.venue == .privateCloudCompute)
        #expect(summary.cloudFallback == nil)
        #expect(device.calls.value.isEmpty)
        #expect(remote.digestCalls.isEmpty)
        #expect(remote.summarizeCalls.count == 1)
        #expect(lineNumbers(in: try #require(remote.summarizeCalls.first?.prompt)) == Array(1...240))
        // Every snapshot, the first (before any words) included, says where.
        #expect(!snapshots.value.isEmpty)
        #expect(snapshots.value.allSatisfy { $0.venue == .privateCloudCompute })
        #expect(snapshots.value.first?.hasText == false)
        // A one-pass run is timed, for Siri's estimate.
        #expect(cloud.recorded.value.count == 1)
    }

    /// The context size comes from the model: a cloud with less room reads
    /// in more parts, but still fewer than the Mac.
    @Test func theCloudsContextSetsItsParts() async {
        let request = F.request(F.chatter(600))
        let router = CatchUpRouter(
            onDevice: onDevice(),
            cloud: FakeCloud(model: FakeCatchUpModel(context: 8192))
        )
        let plan = await router.plan(request)
        let devicePlan = await CatchUpRouter(onDevice: onDevice(), cloud: nil).plan(request)
        #expect(plan.venue == .privateCloudCompute)
        #expect(plan.passes > 1)
        #expect(plan.passes < devicePlan.passes)
        #expect(plan.estimatedSeconds == 10 * Double(plan.passes))

        let roomy = await CatchUpRouter(onDevice: onDevice(), cloud: FakeCloud(model: cloudModel())).plan(request)
        #expect(roomy.isOnePass)
        #expect(roomy.venue == .privateCloudCompute)
    }

    @Test func withoutTheSettingALongStretchStaysOnTheMac() async throws {
        let device = onDevice()
        let router = CatchUpRouter(onDevice: device, cloud: nil)
        let summary = try await router.run(F.request(F.chatter(240)))
        #expect(summary.venue == .onDevice)
        #expect(summary.cloudFallback == nil)
        #expect(!device.digestCalls.isEmpty)

        let plan = await router.plan(F.request(F.chatter(240)))
        #expect(plan.venue == .onDevice)
        #expect(plan.passes > 1)
        #expect(plan.cloudFallback == nil)
    }

    // MARK: Falling back

    @Test func unavailableFallsBackToTheMacQuietly() async throws {
        for reason in [CatchUpCloudFallback.unavailable, .limitReached] {
            let device = onDevice()
            let router = CatchUpRouter(onDevice: device, cloud: FakeCloud { .notReady(reason) })
            let snapshots = Recorder<[CatchUpSummary]>([])
            let summary = try await router.run(F.request(F.chatter(240))) { snapshot in
                snapshots.update { $0.append(snapshot) }
            }
            #expect(summary.overview == "From the Mac.")
            #expect(summary.venue == .onDevice)
            #expect(summary.cloudFallback == reason)
            #expect(!device.digestCalls.isEmpty)
            #expect(snapshots.value.allSatisfy { $0.cloudFallback == reason && $0.venue == .onDevice })

            let plan = await router.plan(F.request(F.chatter(240)))
            #expect(plan.venue == .onDevice)
            #expect(plan.cloudFallback == reason)
        }
    }

    /// Private Cloud Compute fails partway (unreachable, the daily limit,
    /// or anything else it reports): the Mac summarizes the stretch.
    @Test func aCloudFailureFallsBackToTheMac() async throws {
        for reason in [CatchUpCloudFallback.unavailable, .limitReached] {
            let device = onDevice()
            let remote = FakeCatchUpModel(context: 32_768, steps: { _ in
                [.draft(CatchUpDraft(overview: "Half from the cloud")), .fail(.cloudUnavailable(reason))]
            })
            let cloud = FakeCloud(model: remote)
            let router = CatchUpRouter(onDevice: device, cloud: cloud)
            let snapshots = Recorder<[CatchUpSummary]>([])

            let summary = try await router.run(F.request(F.chatter(240))) { snapshot in
                snapshots.update { $0.append(snapshot) }
            }
            #expect(summary.overview == "From the Mac.")
            #expect(summary.venue == .onDevice)
            #expect(summary.cloudFallback == reason)
            #expect(remote.summarizeCalls.count == 1)
            #expect(!device.digestCalls.isEmpty)
            #expect(snapshots.value.contains { $0.overview == "Half from the cloud" && $0.venue == .privateCloudCompute })
            #expect(snapshots.value.last?.cloudFallback == reason)
            #expect(cloud.recorded.value.isEmpty)
            // Remembered, so it isn't tried again straight away.
            #expect(cloud.failures.value == [reason])
        }
    }

    /// What the engine handles itself (a part that's declined) isn't a
    /// reason to leave Private Cloud Compute.
    @Test func aDeclinedPartStaysWithPrivateCloudCompute() async throws {
        let device = onDevice()
        let remote = FakeCatchUpModel(
            context: 32_768,
            digest: { prompt in
                if lineNumbers(in: prompt).contains(1) { throw CatchUpModelError.declined }
                return CatchUpDraft(overview: "A part.")
            },
            final: { prompt in
                if lineNumbers(in: prompt).contains(1) { throw CatchUpModelError.declined }
                return [CatchUpDraft(overview: "Most of it, from the cloud.")]
            }
        )
        let router = CatchUpRouter(onDevice: device, cloud: FakeCloud(model: remote))
        let summary = try await router.run(F.request(F.chatter(240)))
        #expect(summary.venue == .privateCloudCompute)
        #expect(summary.skippedMessages > 0)
        #expect(device.calls.value.isEmpty)
    }

    // MARK: Private Cloud Compute's errors

    @Test func privateCloudComputeErrorsMeanFallingBack() throws {
        guard #available(macOS 27.0, *) else { return }
        typealias PCC = PrivateCloudComputeCatchUpModel
        typealias CloudError = PrivateCloudComputeLanguageModel.Error
        let quota = CloudError.quotaLimitReached(.init(debugDescription: "limit"))
        #expect(PCC.classify(quota) as? CatchUpModelError == .cloudUnavailable(.limitReached))
        let network = CloudError.networkFailure(.init(debugDescription: "offline"))
        #expect(PCC.classify(network) as? CatchUpModelError == .cloudUnavailable(.unavailable))
        let service = CloudError.serviceUnavailable(.init(debugDescription: "down"))
        #expect(PCC.classify(service) as? CatchUpModelError == .cloudUnavailable(.unavailable))
        // What an app without the Private Cloud Compute entitlement gets.
        let refused = NSError(domain: "FoundationModels.LanguageModelError", code: -1)
        #expect(PCC.classify(refused) as? CatchUpModelError == .cloudUnavailable(.unavailable))
        let busy = LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "busy"))
        #expect(PCC.classify(busy) as? CatchUpModelError == .cloudUnavailable(.unavailable))

        // The engine's own business stays with it.
        let tooLong = LanguageModelError.contextSizeExceeded(.init(contextSize: 1, tokenCount: 2, debugDescription: "long"))
        #expect(PCC.classify(tooLong) as? CatchUpModelError == .contextExceeded)
        let guardrail = LanguageModelError.guardrailViolation(.init(debugDescription: "no"))
        #expect(PCC.classify(guardrail) as? CatchUpModelError == .declined)
        #expect(PCC.classify(CancellationError()) is CancellationError)
    }

    /// The engine passes a cloud failure up for the router, rather than
    /// turning it into an error the reader sees.
    @Test func theEnginePassesCloudFailuresUp() async {
        let model = FakeCatchUpModel(final: { _ in throw CatchUpModelError.cloudUnavailable(.limitReached) })
        await #expect(throws: CatchUpModelError.cloudUnavailable(.limitReached)) {
            try await CatchUpEngine(model: model).run(F.request(F.chatter(3)))
        }
    }

    // MARK: Timing

    @Test func timingsStartWithAnEstimateAndFollowMeasurements() {
        let timings = CatchUpCloudTimings()
        #expect(timings.onePassSeconds == CatchUpCloudTimings.defaultOnePassSeconds)
        #expect(timings.estimatedSeconds(passes: 1) == CatchUpCloudTimings.defaultOnePassSeconds)
        timings.record(onePass: .seconds(8))
        #expect(timings.onePassSeconds == 8)
        timings.record(onePass: .seconds(4))
        #expect(timings.onePassSeconds == 6)
        // Three parts, then a merge.
        #expect(timings.estimatedSeconds(passes: 3) == 24)
    }

    /// After a failure, Private Cloud Compute sits out for a while (an app
    /// it refuses would otherwise try, and fail, every time); a success
    /// ends that.
    @Test func aFailureIsRememberedForAWhile() {
        let timings = CatchUpCloudTimings()
        #expect(timings.recentFailure == nil)
        timings.record(failure: .unavailable)
        #expect(timings.recentFailure == .unavailable)
        timings.record(failure: .limitReached)
        #expect(timings.recentFailure == .limitReached)
        timings.record(onePass: .seconds(5))
        #expect(timings.recentFailure == nil)
        #expect(CatchUpCloudTimings.cooldown == .seconds(600))
    }

    @Test func aRecentFailureKeepsPrivateCloudComputeOut() async {
        guard #available(macOS 27.0, *) else { return }
        let timings = CatchUpCloudTimings()
        timings.record(failure: .unavailable)
        let readiness = await PrivateCloudComputeCloud(timings: timings).prepare()
        guard case .notReady(.unavailable) = readiness else {
            Issue.record("Expected Private Cloud Compute to sit out after a failure")
            return
        }
    }

    // MARK: The setting

    /// Private Cloud Compute is offered to the router only while the
    /// setting is on, and only on macOS 27 or later.
    @MainActor
    @Test func theSettingGatesPrivateCloudCompute() throws {
        var allowed = false
        let summarizer = FoundationModelSummarizer(availability: .fixed(.available)) { allowed }
        #expect(try summarizer.router(checkingAvailability: true).cloud == nil)
        allowed = true
        let cloud = try summarizer.router(checkingAvailability: true).cloud
        if #available(macOS 27.0, *) {
            #expect(cloud is PrivateCloudComputeCloud)
        } else {
            #expect(cloud == nil)
        }
        // Without the setting's closure, it's off.
        #expect(try FoundationModelSummarizer(availability: .fixed(.available)).router(checkingAvailability: true).cloud == nil)
    }

    @MainActor
    @Test func unavailableAppleIntelligenceStillFails() {
        let summarizer = FoundationModelSummarizer(availability: .fixed(.turnedOff)) { true }
        #expect(throws: CatchUpError.unavailable(.turnedOff)) {
            try summarizer.router(checkingAvailability: true)
        }
    }
}
