import Foundation

/// A-08: the automation seams.
///
/// Two hot singletons — `CameraAutomationManager` (1076 lines) and
/// `AutomationEngine` — were reached as `.shared` from every layer, which
/// made the automation feature impossible to exercise in a test and impossible
/// to replace. These protocols describe exactly what the UI layer consumes,
/// nothing more.
///
/// The split matters: consumers reach *through* the manager to the engine
/// (`automationManager.ruleStore.rules`) far more often than they call
/// the manager itself, so a single flat protocol would have had to re-expose
/// the whole engine anyway. Splitting rule storage from orchestration keeps
/// each contract small and lets a test fake either half.
///
/// Rules for extending this file (see also CameraCapabilities.swift):
/// - Only add what a consumer calls today. Every member here is a member a
///   test double now has to implement.
/// - No default implementations that reach for `.shared`. That would restore
///   the very coupling being removed.
/// - Data types (`AutomationRule`, `AnalysisRequirements`, `AutomationPlan`)
///   stay concrete. They are values, not collaborators.
protocol AutomationRuleStoring: AnyObject {
    var rules: [AutomationRule] { get }

    var analysisRequirements: AnalysisRequirements { get }

    func addRule(_ rule: AutomationRule, after afterRuleId: String?)

    func updateRule(_ rule: AutomationRule)

    func deleteRule(_ id: String)

    /// Builds the settings a matched rule wants applied. Pure w.r.t. the store —
    /// it reads rules and returns a plan.
    func composeSettings(
        for analysis: SceneAnalysis,
        motionLevel: Double?,
        captureState: CaptureEventState?,
        limitedTo limitedRules: [AutomationRule]?
    ) -> (plan: AutomationPlan, matchedRules: [AutomationRule])
}

/// Refines `ObservableObject` because several consumers hold it as
/// `@ObservedObject` — the automation state has to keep redrawing the UI.
@MainActor
protocol AutomationControlling: AnyObject, ObservableObject {
    /// Rule storage, as a protocol so the UI can be pointed at a stub.
    ///
    /// Named `ruleStore` rather than `automationEngine` on purpose: a
    /// concrete-typed property cannot witness an existential-typed
    /// requirement (Swift reports "candidate has non-matching type"), so the
    /// implementation has to provide a typed shim — and that needs a
    /// different name from the concrete property it wraps.
    var ruleStore: any AutomationRuleStoring { get }

    var executionHistory: [AutomationExecutionHistory] { get }

    /// Clears the history. A method rather than a settable array so the
    /// protocol does not hand consumers a mutable view of internal state.
    func clearExecutionHistory()

    /// Non-nil while the app is waiting for the user to confirm rules.
    var pendingConfirmation: PendingConfirmation? { get }

    /// Weak in the implementation: something owns the sample buffers.
    var sampleBufferProvider: SampleBufferProvider? { get }

    func activateAutomation()

    func deactivateAutomation()

    func executeRuleOnce(_ rule: AutomationRule) async -> Bool

    func triggerBeforeCapture() async

    func triggerAfterCapture() async

    func confirmPendingRules()

    func dismissPendingRules()
}
