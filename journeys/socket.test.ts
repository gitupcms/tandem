import { expect } from "bun:test";
import { journey } from "tandem-kit";

// The same app over the in-app debug socket (debug builds): same answers as stdio, state kept per app.
const MUG = "gid://shop/Product/1";

journey("adjust a product over the debug socket", async app => {
  await app.precondition("ProductList");
  await app.do("Open", { id: MUG }, s => s.name === "ProductDetail" && s.state.quantity === 5);
  await app.do("Increment", undefined, s => s.state.quantity === 6);
  await app.do("Back", undefined, s => s.name === "ProductList");
  expect(app.screen!.state.products[0].quantity).toBe(6);
  await app.expectError(() => app.do("Increment"), "action");
}, { app: "inventory-debug", fixture: "default", socket: true });
