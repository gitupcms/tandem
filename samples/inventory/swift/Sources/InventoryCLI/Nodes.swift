import InventoryCore
import TandemKit

// The app tree: which child each node shows, and which view state it projects. State JSON and action
// schemas/decoding are generated in Core by the introspection macros.

func appNode(_ m: AppModel) -> Node {
    ScreenNode(name: "App", child: { tabsNode(m) })
}

func tabsNode(_ m: AppModel) -> Node {
    ScreenNode(name: "Tabs", actions: { App.Action.actions(m.send) }, child: {
        switch m.state.tab {
        case .inventory: return inventoryStackNode(m)
        case .settings: return ScreenNode(name: "Settings", state: { m.state.settings.introspectionJSON },
                                          actions: { Settings.Action.actions(m.send) })
        }
    })
}

func inventoryStackNode(_ m: AppModel) -> Node {
    ScreenNode(name: "InventoryStack", actions: { App.StackAction.actions(m.send) }, child: {
        switch m.state.stack.last! {
        case .list:
            return ScreenNode(name: "ProductList",
                              state: { ProductList.view(m.state.list, threshold: m.state.settings.lowStockThreshold).introspectionJSON },
                              actions: { ProductList.Action.actions(m.send) })
        case .detail(let d):
            return ScreenNode(name: "ProductDetail", state: { ProductDetail.view(d).introspectionJSON },
                              actions: { ProductDetail.Action.actions(m.send) })
        }
    })
}
