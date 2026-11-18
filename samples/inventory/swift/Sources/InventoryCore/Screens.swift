// Screen view models: State, public Action, internal Message, and a pure `update` that may ask for a service
// call (Effect). AppModel runs effects and feeds their results back as messages. `ViewState` is what a screen
// shows; the macros generate its JSON and the actions' input schemas and decoding.

import TandemIntrospection

public enum ProductList {
    @IntrospectableEnum
    public enum Status: String { case loaded, failed }

    public struct State: Equatable {
        public var status = Status.loaded
        public var error = ""
        public var products: [Product] = []
    }

    @Introspectable
    public struct Row: Equatable {
        public let id: String
        public let title: String
        public let quantity: Int
        public let lowStock: Bool
    }

    @IntrospectableActions
    public enum Action: Equatable {
        case open(id: String)
        case retry
    }

    enum Message {
        case view(Action)
        case fetched(Result<[Product], ServiceError>)
    }

    enum Effect: Equatable {
        case fetch
        case open(Product)
    }

    static func update(_ s: inout State, _ m: Message) -> Effect? {
        switch m {
        case .view(.open(let id)): return s.products.first { $0.id == id }.map(Effect.open)
        case .view(.retry): return .fetch
        case .fetched(.success(let products)): s = State(status: .loaded, error: "", products: products)
        case .fetched(.failure(let e)): s = State(status: .failed, error: e.message, products: [])
        }
        return nil
    }

    public static func rows(_ s: State, threshold: Int) -> [Row] {
        s.products.map { Row(id: $0.id, title: $0.title, quantity: $0.quantity, lowStock: $0.quantity <= threshold) }
    }

    @Introspectable
    public struct ViewState {
        public let status: Status
        public let error: String
        public let products: [Row]
    }

    public static func view(_ s: State, threshold: Int) -> ViewState {
        ViewState(status: s.status, error: s.error, products: rows(s, threshold: threshold))
    }
}

public enum ProductDetail {
    public struct State: Equatable {
        public var product: Product
        public var message = ""
    }

    @IntrospectableActions
    public enum Action: Equatable {
        case increment
        case decrement
    }

    enum Message {
        case view(Action)
        case adjusted(delta: Int, Result<Void, ServiceError>)
    }

    enum Effect: Equatable {
        case adjust(id: String, delta: Int)
    }

    @Introspectable
    public struct ViewState {
        public let id: String
        public let title: String
        public let sku: String
        public let price: String
        public let quantity: Int
        public let message: String
    }

    public static func view(_ s: State) -> ViewState {
        let p = s.product
        return ViewState(id: p.id, title: p.title, sku: p.sku, price: p.price, quantity: p.quantity, message: s.message)
    }

    static let belowZero = "Quantity cannot go below zero"

    static func update(_ s: inout State, _ m: Message) -> Effect? {
        switch m {
        case .view(.increment): return .adjust(id: s.product.id, delta: 1)
        case .view(.decrement):
            if s.product.quantity == 0 { s.message = belowZero; return nil }
            return .adjust(id: s.product.id, delta: -1)
        case .adjusted(let delta, .success):
            s.product.quantity += delta
            s.message = ""
        case .adjusted(_, .failure(let e)): s.message = e.message
        }
        return nil
    }
}

public enum Settings {
    @Introspectable
    public struct State: Equatable {
        public var lowStockThreshold = 3
        public var message = ""
    }

    @IntrospectableActions
    public enum Action: Equatable {
        case setThreshold(value: Int64)
    }

    enum Message {
        case view(Action)
    }

    static let outOfRange = "Threshold must be between 0 and 1000"

    static func update(_ s: inout State, _ m: Message) {
        switch m {
        case .view(.setThreshold(let v)):
            if (0...1000).contains(v) {
                s.lowStockThreshold = Int(v)
                s.message = ""
            } else {
                s.message = outOfRange
            }
        }
    }
}
