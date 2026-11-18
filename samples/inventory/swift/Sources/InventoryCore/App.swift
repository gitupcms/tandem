/// Root view model: tabs, the inventory stack, and the screens' states. Quantity changes in a detail are
/// written back to the list here, so both screens show the same product.
import TandemIntrospection

public enum App {
    @IntrospectableEnum
    public enum Tab: String { case inventory, settings }

    public enum Route: Equatable {
        case list
        case detail(ProductDetail.State)
    }

    public struct State: Equatable {
        public var tab = Tab.inventory
        public var stack: [Route] = [.list]
        public var list = ProductList.State()
        public var settings = Settings.State()
    }

    @IntrospectableActions
    public enum Action: Equatable {
        case selectTab(tab: Tab)
    }

    /// Actions of the inventory stack.
    @IntrospectableActions
    public enum StackAction: Equatable {
        case back
    }

    enum Message {
        case view(Action)
        case stack(StackAction)
        case list(ProductList.Message)
        case detail(ProductDetail.Message)
        case settings(Settings.Message)
    }

    enum Effect: Equatable {
        case fetch
        case adjust(id: String, delta: Int)
    }

    static func update(_ s: inout State, _ m: Message) -> Effect? {
        switch m {
        case .view(.selectTab(let tab)): s.tab = tab
        case .stack(.back): if s.stack.count > 1 { s.stack.removeLast() }
        case .list(let m):
            switch ProductList.update(&s.list, m) {
            case .fetch?: return .fetch
            case .open(let p)?: s.stack.append(.detail(ProductDetail.State(product: p)))
            case nil: break
            }
        case .detail(let m):
            guard case .detail(var d)? = s.stack.last else { return nil }
            let effect = ProductDetail.update(&d, m)
            s.stack[s.stack.count - 1] = .detail(d)
            if let i = s.list.products.firstIndex(where: { $0.id == d.product.id }) { s.list.products[i].quantity = d.product.quantity }
            if case .adjust(let id, let delta)? = effect { return .adjust(id: id, delta: delta) }
        case .settings(let m): Settings.update(&s.settings, m)
        }
        return nil
    }
}

public final class AppModel {
    public private(set) var state = App.State()
    let service: InventoryService

    public init(service: InventoryService) {
        self.service = service
        dispatch(.list(.view(.retry))) // fetch once at start
    }

    public func send(_ action: App.Action) { dispatch(.view(action)) }
    public func send(_ action: App.StackAction) { dispatch(.stack(action)) }
    public func send(_ action: ProductList.Action) { dispatch(.list(.view(action))) }
    public func send(_ action: ProductDetail.Action) { dispatch(.detail(.view(action))) }
    public func send(_ action: Settings.Action) { dispatch(.settings(.view(action))) }

    func dispatch(_ message: App.Message) {
        var next: App.Message? = message
        while let m = next { next = App.update(&state, m).map(run) }
    }

    private func run(_ effect: App.Effect) -> App.Message {
        switch effect {
        case .fetch: return .list(.fetched(service.fetchProducts()))
        case .adjust(let id, let delta): return .detail(.adjusted(delta: delta, service.adjust(productId: id, delta: delta)))
        }
    }
}
