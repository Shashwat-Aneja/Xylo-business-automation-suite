export function createDeliveryLogger({
  supabaseUrl = process.env.SUPABASE_URL,
  serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY,
  fetchImpl = fetch,
} = {}) {
  if (!supabaseUrl || !serviceRoleKey) throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.");
  const baseUrl = supabaseUrl.replace(/\/$/, "");
  return async function logAttempt({ userId, recipientEmail, messageType, status, providerMessageId = null, errorCode = null }) {
    const response = await fetchImpl(`${baseUrl}/rest/v1/email_delivery_attempts`, {
      method: "POST",
      headers: {
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify({
        user_id: userId,
        recipient_email: recipientEmail,
        message_type: messageType,
        status,
        provider_message_id: providerMessageId,
        error_code: errorCode,
      }),
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error("Could not persist email delivery audit record.");
  };
}
