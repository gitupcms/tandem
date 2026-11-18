import InventoryCore
import TandemKit

// Node adapters: map view model state to JSON and validated input to actions. No business rules here.

final class AppNode: Node {
    let model: AppModel
    init(_ model: AppModel) { self.model = model }

    let name = "App"
    var child: Node? { TabsNode(model) }
}

final class TabsNode: Node {
    let model: AppModel
    init(_ model: AppModel) { self.model = model }

    let name = "Tabs"
    var actions: [Action] {
        let m = model
        return [Action("SelectTab", input: .object([("tab", .string(enum: ["inventory", "settings"]))], required: ["tab"])) { i in
            if let tab = i?["tab"]?.stringValue.flatMap(App.Tab.init(rawValue:)) { m.send(App.Action.selectTab(tab)) }
        }]
    }
    var child: Node? {
        switch model.state.tab {
        case .inventory: return InventoryStackNode(model)
        case .settings: return SettingsNode(model)
        }
    }
}

final class InventoryStackNode: Node {
    let model: AppModel
    init(_ model: AppModel) { self.model = model }

    let name = "InventoryStack"
    var actions: [Action] { [Action("Back") { [model] _ in model.send(App.Action.back) }] }
    var child: Node? {
        switch model.state.stack.last! {
        case .list: return ProductListNode(model)
        case .detail(let d): return ProductDetailNode(model, d)
        }
    }
}

final class ProductListNode: Node {
    let model: AppModel
    init(_ model: AppModel) { self.model = model }

    let name = "ProductList"
    var state: JSON {
        let s = model.state
        return .object([
            ("status", .string(s.list.status.rawValue)),
            ("error", .string(s.list.error)),
            ("products", .array(ProductList.rows(s.list, threshold: s.settings.lowStockThreshold).map { r in
                .object([("id", .string(r.id)), ("lowStock", .bool(r.lowStock)), ("quantity", .integer(Int64(r.quantity))), ("title", .string(r.title))])
            })),
        ])
    }
    var actions: [Action] {
        let m = model
        return [
            Action("Open", input: .object([("id", .string())], required: ["id"])) { i in
                m.send(ProductList.Action.open(id: i?["id"]?.stringValue ?? ""))
            },
            Action("Retry") { _ in m.send(ProductList.Action.retry) },
        ]
    }
}

final class ProductDetailNode: Node {
    let model: AppModel
    let detail: ProductDetail.State
    init(_ model: AppModel, _ detail: ProductDetail.State) {
        self.model = model
        self.detail = detail
    }

    let name = "ProductDetail"
    var state: JSON {
        let p = detail.product
        return .object([
            ("id", .string(p.id)), ("title", .string(p.title)), ("sku", .string(p.sku)), ("price", .string(p.price)),
            ("quantity", .integer(Int64(p.quantity))), ("message", .string(detail.message)),
        ])
    }
    var actions: [Action] {
        let m = model
        return [
            Action("Increment") { _ in m.send(ProductDetail.Action.increment) },
            Action("Decrement") { _ in m.send(ProductDetail.Action.decrement) },
        ]
    }
}

final class SettingsNode: Node {
    let model: AppModel
    init(_ model: AppModel) { self.model = model }

    let name = "Settings"
    var state: JSON {
        let s = model.state.settings
        return .object([("lowStockThreshold", .integer(Int64(s.lowStockThreshold))), ("message", .string(s.message))])
    }
    var actions: [Action] {
        let m = model
        return [Action("SetThreshold", input: .object([("value", .integer)], required: ["value"])) { i in
            if let v = JSON.int(i?["value"]) { m.send(Settings.Action.setThreshold(v)) }
        }]
    }
}
