export function createSupabaseAuth({ supabaseUrl = process.env.SUPABASE_URL, publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY, fetchImpl = fetch } = {}) {
  if (!supabaseUrl || !publishableKey) throw new Error("SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY are required.");
  const baseUrl = supabaseUrl.replace(/\/$/, "");
  return async function requireSupabaseUser(req, res, next) {
    const match = /^Bearer\s+(.+)$/i.exec(req.get("authorization") ?? "");
    if (!match) return res.status(401).json({ error: "Authentication required." });
    try {
      const response = await fetchImpl(`${baseUrl}/auth/v1/user`, {
        headers: { apikey: publishableKey, Authorization: `Bearer ${match[1]}` },
        signal: AbortSignal.timeout(5000),
      });
      if (!response.ok) return res.status(401).json({ error: "Invalid or expired session." });
      const user = await response.json();
      if (!user?.id || !user?.email) return res.status(401).json({ error: "Authenticated account email is unavailable." });
      req.xyloUser = { id: user.id, email: user.email, name: user.user_metadata?.full_name ?? user.user_metadata?.name ?? "" };
      return next();
    } catch {
      return res.status(503).json({ error: "Authentication service temporarily unavailable." });
    }
  };
}
