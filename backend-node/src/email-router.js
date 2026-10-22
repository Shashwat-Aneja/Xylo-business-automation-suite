import { Router } from "express";
import { testEmail } from "./templates.js";

export function createEmailRouter({ requireUser, mailClient, logAttempt, now = () => Date.now(), limit = 3, windowMs = 60 * 60 * 1000 }) {
  const router = Router();
  const sendsByUser = new Map();

  router.post("/test", requireUser, async (req, res) => {
    const user = req.xyloUser;
    if (!user?.id || !user?.email) return res.status(401).json({ error: "Authenticated account email is unavailable." });

    const timestamp = now();
    const current = (sendsByUser.get(user.id) ?? []).filter((time) => timestamp - time < windowMs);
    if (current.length >= limit) return res.status(429).json({ error: "Test email limit reached. Try again later." });
    current.push(timestamp);
    sendsByUser.set(user.id, current);

    let messageId = null;
    try {
      const message = testEmail({ recipientName: user.name });
      const result = await mailClient.send({ to: user.email, ...message });
      messageId = result.id;
      await logAttempt({
        userId: user.id, recipientEmail: user.email, messageType: "account_email_test",
        status: "accepted", providerMessageId: messageId,
      });
      return res.status(202).json({ status: "accepted", messageId });
    } catch (error) {
      try {
        await logAttempt({
          userId: user.id, recipientEmail: user.email, messageType: "account_email_test",
          status: "failed", providerMessageId: messageId,
          errorCode: error?.name === "MailDeliveryError" ? "provider_rejected_or_unavailable" : "delivery_log_or_send_failure",
        });
      } catch { /* Never leak internal logging details or credentials. */ }
      return res.status(502).json({ error: "Email could not be sent or audited. Check server logs." });
    }
  });

  return router;
}
