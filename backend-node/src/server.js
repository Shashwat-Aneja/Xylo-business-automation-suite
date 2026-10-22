import express from "express";
import { createResendClient } from "./resend.js";
import { createSupabaseAuth } from "./supabase-auth.js";
import { createDeliveryLogger } from "./delivery-log.js";
import { createEmailRouter } from "./email-router.js";

const app = express();
app.disable("x-powered-by");
app.use(express.json({ limit: "16kb" }));

app.get("/health", (_req, res) => res.json({ status: "ok" }));

if (process.env.NODE_ENV !== "test") {
  const mailClient = createResendClient();
  const requireUser = createSupabaseAuth();
  const logAttempt = createDeliveryLogger();
  app.use("/api/email", createEmailRouter({ requireUser, mailClient, logAttempt }));
}

const port = Number(process.env.PORT ?? 4100);
if (process.env.NODE_ENV !== "test") {
  app.listen(port, () => process.stdout.write(`Xylo mail API listening on ${port}\n`));
}

export default app;
