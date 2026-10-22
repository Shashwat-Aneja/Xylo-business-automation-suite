const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const RESEND_URL = "https://api.resend.com/emails";

export class MailConfigurationError extends Error {}
export class MailDeliveryError extends Error {}

export function createResendClient({
  apiKey = process.env.RESEND_API_KEY,
  from = process.env.RESEND_FROM_EMAIL,
  fetchImpl = fetch,
  timeoutMs = 10_000,
} = {}) {
  if (!apiKey?.trim()) throw new MailConfigurationError("RESEND_API_KEY is not configured.");
  const sender = from?.trim() ?? "";
  const senderAddress = sender.includes("<") ? sender.split("<").at(-1).replace(/>\s*$/, "").trim() : sender;
  if (!EMAIL_RE.test(senderAddress)) {
    throw new MailConfigurationError("RESEND_FROM_EMAIL must contain a valid address on the verified sending domain.");
  }

  return {
    async send({ to, subject, html, text }) {
      if (typeof to !== "string" || !EMAIL_RE.test(to.trim())) throw new TypeError("Recipient email address is invalid.");
      if (typeof subject !== "string" || !subject.trim()) throw new TypeError("Email subject cannot be empty.");
      if (!(typeof html === "string" && html.trim()) && !(typeof text === "string" && text.trim())) {
        throw new TypeError("Provide HTML or plain-text email content.");
      }

      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      try {
        const response = await fetchImpl(RESEND_URL, {
          method: "POST",
          headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json", "User-Agent": "Xylo-Transactional-Mail/1.0" },
          body: JSON.stringify({ from: sender, to: [to.trim()], subject: subject.trim(), html, text }),
          signal: controller.signal,
        });
        const body = await response.json().catch(() => ({}));
        if (!response.ok || typeof body.id !== "string" || !body.id) {
          throw new MailDeliveryError(`Resend rejected the message (HTTP ${response.status}).`);
        }
        return { id: body.id };
      } catch (error) {
        if (error instanceof MailDeliveryError) throw error;
        if (error?.name === "AbortError") throw new MailDeliveryError("Resend request timed out.");
        throw new MailDeliveryError("Resend request failed.");
      } finally {
        clearTimeout(timer);
      }
    },
  };
}
