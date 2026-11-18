import XCTest
@testable import InventoryCore

final class StubService: InventoryService {
    var products: Result<[Product], ServiceError> = .success([Product(id: "1", title: "Mug", sku: "M", price: "1.00", quantity: 0)])
    var adjustResult: Result<Void, ServiceError> = .success(())
    var adjustCalls = 0

    func fetchProducts() -> Result<[Product], ServiceError> { products }
    func adjust(productId: String, delta: Int) -> Result<Void, ServiceError> {
        adjustCalls += 1
        return adjustResult
    }
}

final class UpdateTests: XCTestCase {
    func testDecrementAtZeroRefusesWithoutEffect() {
        var s = ProductDetail.State(product: Product(id: "1", title: "", sku: "", price: "", quantity: 0))
        XCTAssertNil(ProductDetail.update(&s, .view(.decrement)))
        XCTAssertEqual(s.message, "Quantity cannot go below zero")
    }

    func testFailedAdjustKeepsQuantity() {
        var s = ProductDetail.State(product: Product(id: "1", title: "", sku: "", price: "", quantity: 4))
        XCTAssertEqual(ProductDetail.update(&s, .view(.increment)), .adjust(id: "1", delta: 1))
        _ = ProductDetail.update(&s, .adjusted(delta: 1, .failure(ServiceError("locked"))))
        XCTAssertEqual(s.product.quantity, 4)
        XCTAssertEqual(s.message, "locked")
    }

    func testThresholdRange() {
        var s = Settings.State()
        Settings.update(&s, .view(.setThreshold(-1)))
        XCTAssertEqual(s, Settings.State(lowStockThreshold: 3, message: "Threshold must be between 0 and 1000"))
        Settings.update(&s, .view(.setThreshold(1000)))
        XCTAssertEqual(s, Settings.State(lowStockThreshold: 1000, message: ""))
    }

    func testFetchFailureClearsProducts() {
        var s = ProductList.State(status: .loaded, error: "", products: [Product(id: "1", title: "", sku: "", price: "", quantity: 1)])
        _ = ProductList.update(&s, .fetched(.failure(ServiceError("down"))))
        XCTAssertEqual(s, ProductList.State(status: .failed, error: "down", products: []))
    }

    func testDetailQuantityIsSharedWithList() {
        let service = StubService()
        let app = AppModel(service: service)
        app.send(ProductList.Action.open(id: "1"))
        app.send(ProductDetail.Action.decrement) // refused at zero: no service call
        XCTAssertEqual(service.adjustCalls, 0)
        app.send(ProductDetail.Action.increment)
        app.send(App.Action.back)
        app.send(App.Action.back) // stack root: no change
        XCTAssertEqual(app.state.stack, [.list])
        XCTAssertEqual(ProductList.rows(app.state.list, threshold: 0).first?.lowStock, false)
        XCTAssertEqual(app.state.list.products.first?.quantity, 1)
    }
}
