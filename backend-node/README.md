# Xylo transactional mail API (Node.js + Express)

This is the Node.js implementation target for Xylo email. It is isolated from the existing Python demo backend while the broader migration is reviewed.

## Runtime

Node.js 20+ (CI currently tests Node 22). From this directory run `npm install`, then `npm start`.

Required server-only environment variables:
- `RESEND_API_KEY`: domain-restricted sending-only Resend key. Rotate it first if it was ever exposed.
- `RESEND_FROM_EMAIL`: `Xylo <mail@mail.shashwataneja.com>`
- `SUPABASE_URL`: the project's HTTPS URL.
- `SUPABASE_PUBLISHABLE_KEY`: Supabase publishable key, used only for Auth user validation.
- `SUPABASE_SERVICE_ROLE_KEY`: server-only privileged key used to write audit rows. Never use it in browser code, commit it, or expose it in responses.

## Endpoint

`POST /api/email/test` requires `Authorization: Bearer <Supabase access token>`. It sends only to the authenticated user's account email, never a client-supplied recipient. It is rate-limited and writes a delivery-attempt audit record. A 202 response means Resend accepted the message; it does **not** prove inbox delivery.

The included in-memory rate limiter is a single-process safety guard, not a distributed limiter. Before public production traffic, replace it with a shared limiter (e.g. Postgres atomic counter or a managed rate-limiting service). The service-role key is required for the audit insert; keep it in the deployment platform's server-side secret store.

## Invoice reminders

The invoice template is implemented and tested, but no invoice-reminder endpoint is exposed yet. The repository has not established a canonical production invoice/customer schema or invoice ownership query. Do not send reminders until the route loads the invoice and recipient from trusted database records and verifies business ownership, invoice state, and recipient consent/appropriateness.

## Deployment checklist

- [ ] Rotate any previously exposed Resend API key; add replacement to backend secret store.
- [ ] Apply `supabase/migrations/202610220001_email_delivery_attempts.sql` to the intended Supabase project after review.
- [ ] Configure the five server environment variables above in a Node-capable backend runtime.
- [ ] Use a persistent shared rate limiter before public production traffic.
- [ ] Deploy to a Node-capable service (not the current static-only frontend deployment).
- [ ] Call `POST /api/email/test` with a valid Supabase access token and verify the controlled inbox and Resend event log.
- [ ] Confirm audit row exists, and check logs for absence of secrets/recipient payloads.
- [ ] Add invoice route only after invoice/customer schema and ownership policy are implemented.
