// Run by sdk.test.ts with TANDEM_CONFIG pointing at two fake hosts.
import { journey } from "tandem-kit";

journey("increment", async app => {
  await app.do("Increment");
  await app.expectError(() => app.do("Nope"), "action");
});
