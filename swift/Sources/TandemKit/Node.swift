/// One node of the app tree. Nodes hold no logic: they report view model state and forward actions.
public protocol Node: AnyObject {
    var name: String { get }
    var state: JSON { get }
    var actions: [Action] { get }
    var child: Node? { get }
}

extension Node {
    public var state: JSON { .object([]) }
    public var actions: [Action] { [] }
    public var child: Node? { nil }
}

public struct Action {
    public let name: String
    public let input: Schema?
    /// Called with the validated input, or nil when the action has no schema.
    public let perform: (JSON?) -> Void

    public init(_ name: String, input: Schema? = nil, perform: @escaping (JSON?) -> Void) {
        self.name = name
        self.input = input
        self.perform = perform
    }
}

/// A node built from closures, read on every request, so it always reflects the current view model.
public final class ScreenNode: Node {
    public let name: String
    private let getState: () -> JSON
    private let getActions: () -> [Action]
    private let getChild: () -> Node?

    public init(name: String, state: @escaping () -> JSON = { .object([]) }, actions: @escaping () -> [Action] = { [] },
                child: @escaping () -> Node? = { nil }) {
        self.name = name
        getState = state
        getActions = actions
        getChild = child
    }

    public var state: JSON { getState() }
    public var actions: [Action] { getActions() }
    public var child: Node? { getChild() }
}
