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
