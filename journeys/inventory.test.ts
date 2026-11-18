import { expect } from "bun:test";
import { journey } from "tandem-kit";

const at = (fixture: string) => ({ app: "inventory", fixture });
const MUG = "gid://shop/Product/1";
const CAP = "gid://shop/Product/3";

journey("list shows products with low stock flags", async app => {
  await app.precondition("ProductList");
  expect(app.screen!.path).toEqual(["App", "Tabs", "InventoryStack", "ProductList"]);
  expect(app.screen!.state).toEqual({
    error: "",
    products: [
      { id: MUG, lowStock: false, quantity: 5, title: "Mug" },
      { id: "gid://shop/Product/2", lowStock: true, quantity: 2, title: "Tote" },
      { id: CAP, lowStock: true, quantity: 0, title: "Cap" },
    ],
    status: "loaded",
  });
  expect(app.screen!.actions.map(a => `${a.from}.${a.name}`)).toEqual([
    "ProductList.Open", "ProductList.Retry", "InventoryStack.Back", "Tabs.SelectTab",
  ]);
}, at("default"));

journey("adjust a product and see it on the list", async app => {
  await app.precondition("ProductList");
  await app.do("Open", { id: MUG }, s => s.name === "ProductDetail" && s.state.quantity === 5);
  expect(app.screen!.state).toEqual({ id: MUG, message: "", price: "12.50", quantity: 5, sku: "MUG-01", title: "Mug" });
  await app.do("Increment", undefined, s => s.state.quantity === 6);
  await app.do("Decrement", undefined, s => s.state.quantity === 5);
  await app.do("Decrement", undefined, s => s.state.quantity === 4);
  await app.do("Back", undefined, s => s.name === "ProductList");
  expect(app.screen!.state.products[0]).toEqual({ id: MUG, lowStock: false, quantity: 4, title: "Mug" });
  await app.do("Back", undefined, s => s.name === "ProductList"); // stack root: no change
}, at("default"));

journey("decrement at zero is refused without a service call", async app => {
  await app.do("Open", { id: CAP }, s => s.name === "ProductDetail");
  await app.do("Decrement", undefined, s => s.state.message === "Quantity cannot go below zero");
  expect(app.screen!.state.quantity).toBe(0);
  await app.do("Increment", undefined, s => s.state.quantity === 1 && s.state.message === "");
}, at("default"));

journey("a locked adjustment keeps the quantity and shows the error", async app => {
  await app.do("Open", { id: MUG }, s => s.name === "ProductDetail");
  await app.do("Increment", undefined, s => s.state.message === "Inventory is locked");
  expect(app.screen!.state.quantity).toBe(5);
  await app.do("Back", undefined, s => s.name === "ProductList");
  await app.do("Open", { id: MUG }, s => s.name === "ProductDetail" && s.state.message === "");
}, at("adjust-locked"));

journey("failed fetch, then retry", async app => {
  await app.precondition(s => s.state.status === "failed");
  expect(app.screen!.state).toEqual({ error: "Service unavailable", products: [], status: "failed" });
  await app.do("Retry", undefined, s => s.state.status === "failed");
  await app.do("Open", { id: MUG }, s => s.name === "ProductList"); // unknown id: no change
}, at("fetch-error"));

journey("empty store", async app => {
  await app.precondition(s => s.name === "ProductList" && s.state.products.length === 0 && s.state.status === "loaded");
}, at("empty"));

journey("threshold changes low stock flags across tabs", async app => {
  await app.do("Open", { id: MUG }, s => s.name === "ProductDetail");
  await app.do("SelectTab", { tab: "settings" }, s => s.name === "Settings");
  expect(app.screen!.path).toEqual(["App", "Tabs", "Settings"]);
  expect(app.screen!.actions.map(a => `${a.from}.${a.name}`)).toEqual(["Settings.SetThreshold", "Tabs.SelectTab"]);
  await app.do("SetThreshold", { value: 1001 }, s => s.state.message === "Threshold must be between 0 and 1000");
  expect(app.screen!.state.lowStockThreshold).toBe(3);
  await app.do("SetThreshold", { value: 5 }, s => s.state.lowStockThreshold === 5 && s.state.message === "");
  await app.do("SelectTab", { tab: "inventory" }, s => s.name === "ProductDetail"); // stack kept
  await app.do("Back", undefined, s => s.name === "ProductList");
  expect(app.screen!.state.products.map((p: { lowStock: boolean }) => p.lowStock)).toEqual([true, true, true]);
}, at("default"));

journey("protocol errors on the sample", async app => {
  await app.precondition("ProductList");
  await app.expectError(() => app.do("Increment"), "action");
  await app.expectError(() => app.do("SelectTab", { tab: "orders" }), "input");
  await app.expectError(() => app.do("Open", {}), "input");
}, at("default"));
