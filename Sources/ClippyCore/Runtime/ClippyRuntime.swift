import Foundation

public actor ClippyRuntime {
    private let actionQueue: MascotActionQueue
    private let toolRouter: ToolRouter
    private var stateMachine: MascotStateMachine

    public init(
        actionQueue: MascotActionQueue = MascotActionQueue(),
        toolRouter: ToolRouter = ToolRouter(),
        initialState: MascotState = .hidden
    ) {
        self.actionQueue = actionQueue
        self.toolRouter = toolRouter
        self.stateMachine = MascotStateMachine(initialState: initialState)
    }

    public var snapshot: MascotStateSnapshot {
        stateMachine.current
    }

    @discardableResult
    public func enqueue(_ command: MascotCommand) async -> MascotRequestSnapshot {
        await actionQueue.enqueue(MascotAction(command: command))
    }

    @discardableResult
    public func startNextAction() async -> MascotRequestSnapshot? {
        guard let started = await actionQueue.startNext() else {
            return nil
        }
        stateMachine.apply(.commandStarted(started.command))
        return started
    }

    @discardableResult
    public func finishCurrentAction(status: MascotRequestStatus = .complete) async -> MascotRequestSnapshot? {
        guard let finished = await actionQueue.finishCurrent(status: status) else {
            return nil
        }
        stateMachine.apply(.commandFinished(finished.command, finished.status))
        return finished
    }

    @discardableResult
    public func handleVoiceEvent(_ event: VoiceEvent) -> MascotStateSnapshot {
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
