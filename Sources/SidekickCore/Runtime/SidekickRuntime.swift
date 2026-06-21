import Foundation

public actor SidekickRuntime {
    private let actionQueue: SidekickActionQueue
    private let toolRouter: ToolRouter
    private var stateMachine: SidekickStateMachine

    public init(
        actionQueue: SidekickActionQueue = SidekickActionQueue(),
        toolRouter: ToolRouter = ToolRouter(),
        initialState: SidekickState = .hidden
    ) {
        self.actionQueue = actionQueue
        self.toolRouter = toolRouter
        self.stateMachine = SidekickStateMachine(initialState: initialState)
    }

    public var snapshot: SidekickStateSnapshot {
        stateMachine.current
    }

    @discardableResult
    public func enqueue(_ command: SidekickCommand) async -> SidekickRequestSnapshot {
        await actionQueue.enqueue(SidekickAction(command: command))
    }

    @discardableResult
    public func startNextAction() async -> SidekickRequestSnapshot? {
        guard let started = await actionQueue.startNext() else {
            return nil
        }
        stateMachine.apply(.commandStarted(started.command))
        return started
    }

    @discardableResult
    public func finishCurrentAction(status: SidekickRequestStatus = .complete) async -> SidekickRequestSnapshot? {
        guard let finished = await actionQueue.finishCurrent(status: status) else {
            return nil
        }
        stateMachine.apply(.commandFinished(finished.command, finished.status))
        return finished
    }

    @discardableResult
    public func handleVoiceEvent(_ event: VoiceEvent) -> SidekickStateSnapshot {
        stateMachine.apply(.voice(event))
    }

    public func registerTool(name: String, executor: any ToolExecuting) async {
        await toolRouter.register(name: name, executor: executor)
    }

    public func routeTool(_ invocation: ToolInvocation, approved: Bool = false) async -> ToolRoutingOutcome {
        stateMachine.apply(.toolStarted(invocation.name))
        let outcome = await toolRouter.route(invocation, approved: approved)
        switch outcome {
        case let .completed(result):
            stateMachine.apply(.toolFinished(result.toolName, result.status))
        case let .approvalRequired(request):
            stateMachine.apply(.approvalRequested(request))
        }
        return outcome
    }
}
