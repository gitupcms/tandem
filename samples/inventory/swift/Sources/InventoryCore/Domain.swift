public struct Product: Equatable {
    public var id: String
    public var title: String
    public var sku: String
    public var price: String
    public var quantity: Int

    public init(id: String, title: String, sku: String, price: String, quantity: Int) {
        self.id = id
        self.title = title
        self.sku = sku
        self.price = price
        self.quantity = quantity
    }
}

public struct ServiceError: Error, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// Synchronous in this sample; results still reach state only through `update`.
public protocol InventoryService {
    func fetchProducts() -> Result<[Product], ServiceError>
    func adjust(productId: String, delta: Int) -> Result<Void, ServiceError>
}
