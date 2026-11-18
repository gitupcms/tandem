import Foundation
import InventoryCore
import TandemKit

/// InventoryService backed by `fixtures/<name>/`; files are read on every call.
struct FixtureService: InventoryService {
    let dir: URL

    private func load(_ file: String) -> Result<JSON, ServiceError> {
        guard let data = FileManager.default.contents(atPath: dir.appendingPathComponent(file).path) else {
            return .failure(ServiceError("cannot read fixture \(file)"))
        }
        do { return .success(try JSON.decode(data)) } catch { return .failure(ServiceError("bad fixture \(file)")) }
    }

    /// First message of a GraphQL-style error list, if any.
    private func firstMessage(_ errors: JSON?) -> String? {
        guard case .array(let xs)? = errors, let first = xs.first else { return nil }
        return first["message"]?.stringValue ?? ""
    }

    func fetchProducts() -> Result<[Product], ServiceError> {
        load("products.json").flatMap { json in
            if let m = firstMessage(json["errors"]) { return .failure(ServiceError(m)) }
            guard case .array(let nodes)? = json["data"]?["products"]?["nodes"] else {
                return .failure(ServiceError("bad fixture products.json"))
            }
            var out: [Product] = []
            for n in nodes {
                guard let id = n["id"]?.stringValue, let title = n["title"]?.stringValue, let sku = n["sku"]?.stringValue,
                      let price = n["price"]?.stringValue, let q = JSON.int(n["quantity"]) else {
                    return .failure(ServiceError("bad fixture products.json"))
                }
                out.append(Product(id: id, title: title, sku: sku, price: price, quantity: Int(q)))
            }
            return .success(out)
        }
    }

    func adjust(productId: String, delta: Int) -> Result<Void, ServiceError> {
        load("adjust.json").flatMap { json in
            guard let errors = json["data"]?["inventoryAdjust"]?["userErrors"] else {
                return .failure(ServiceError("bad fixture adjust.json"))
            }
            if let m = firstMessage(errors) { return .failure(ServiceError(m)) }
            return .success(())
        }
    }
}
