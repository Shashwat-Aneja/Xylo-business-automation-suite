function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[char]);
}

export function testEmail({ recipientName = "there" } = {}) {
  const name = escapeHtml(recipientName.trim() || "there");
  return {
    subject: "Your Xylo email setup is working",
    text: `Hello ${recipientName.trim() || "there"},\n\nThis is a test message confirming Xylo's transactional email service can reach your inbox. No invoice or payment action is associated with this email.\n\n— Xylo`,
    html: `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><body style="margin:0;padding:28px;background:#f3efe6;color:#24231f;font-family:Arial,Helvetica,sans-serif"><main style="max-width:560px;margin:auto;background:#faf8f2;border:1px solid #d7d1c5;padding:32px"><div style="font:32px Georgia,serif">Xylo<span style="color:#873f32">.</span></div><hr style="border:0;border-top:1px solid #d7d1c5;margin:24px 0"><p>Hello ${name},</p><h1 style="font:normal 28px Georgia,serif">Your email setup is working.</h1><p style="line-height:1.7">This test confirms Xylo's transactional email service can reach your inbox. No invoice or payment action is associated with this email.</p><p style="color:#74745d">— Xylo</p></main></body></html>`,
  };
}

export function invoiceReminderEmail({ recipientName, businessName, invoiceNumber, amount, dueDate, invoiceUrl }) {
  const parsed = new URL(invoiceUrl);
  if (parsed.protocol !== "https:") throw new TypeError("Invoice links must use HTTPS.");
  for (const [key, value] of Object.entries({ businessName, invoiceNumber, amount, dueDate })) {
    if (typeof value !== "string" || !value.trim()) throw new TypeError(`${key} is required.`);
  }
  const name = escapeHtml(recipientName?.trim() || "there");
  const business = escapeHtml(businessName.trim());
  const invoice = escapeHtml(invoiceNumber.trim());
  const total = escapeHtml(amount.trim());
  const due = escapeHtml(dueDate.trim());
  const link = escapeHtml(parsed.toString());
  return {
    subject: `Payment reminder: invoice ${invoiceNumber.trim()}`,
    text: `Hello ${recipientName?.trim() || "there"},\n\n${businessName} is reminding you that invoice ${invoiceNumber} for ${amount} was due on ${dueDate}.\n\nReview the invoice: ${parsed.toString()}\n\nIf you have already paid, please disregard this reminder.`,
    html: `<!doctype html><html lang="en"><meta charset="utf-8"><body style="margin:0;padding:28px;background:#f3efe6;color:#24231f;font-family:Arial,Helvetica,sans-serif"><main style="max-width:560px;margin:auto;background:#faf8f2;border:1px solid #d7d1c5;padding:32px"><div style="font:32px Georgia,serif">Xylo<span style="color:#873f32">.</span></div><hr style="border:0;border-top:1px solid #d7d1c5;margin:24px 0"><p>Hello ${name},</p><h1 style="font:normal 28px Georgia,serif">An invoice is ready for your attention.</h1><p>${business} is reminding you that invoice <strong>${invoice}</strong> for <strong>${total}</strong> was due on ${due}.</p><p><a href="${link}" style="display:inline-block;background:#873f32;color:white;padding:12px 18px;text-decoration:none">Review invoice</a></p><p>If you have already paid, please disregard this reminder.</p></main></body></html>`,
  };
}
