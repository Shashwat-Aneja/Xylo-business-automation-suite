# Resend transactional email setup

This integration keeps Resend credentials on the server. Never put `RESEND_API_KEY`
in HTML, browser JavaScript, a `VITE_*` variable, or a committed environment file.

## Current setup status

- Sending domain: `mail.shashwataneja.com`
- Region: `ap-northeast-1`
- Open/click tracking: disabled
- TLS: enforced
- Domain-restricted sending API key: created; **rotate it if it was ever shared in chat, logs, or screenshots**
- Domain verification: **verified** (DKIM, SPF, and tracking CNAME reported verified by Resend)
- Sender identity: `Xylo <mail@mail.shashwataneja.com>`
- Provider adapter, HTML/text template, orchestration helper, unit tests, and CI workflow: committed
- Latest adapter test workflow: passed (see [GitHub Actions run](https://github.com/Shashwat-Aneja/Xylo-business-automation-suite/actions/runs/39741909851))
- Real inbox delivery: **not yet tested**
- Public invoice-reminder endpoint: **intentionally not wired yet**

## DNS records

The following records were configured for the sending subdomain. Keep them in place
while using this Resend sending domain; avoid duplicate SPF TXT records at the same
hostname.

| Type | Name / Host | Value / Target | Priority |
|---|---|---|---:|
| TXT | `resend._domainkey.mail` | DKIM public key configured in DNS | — |
| MX | `send.mail` | `feedback-smtp.ap-northeast-1.amazonses.com` | 10 |
| TXT | `send.mail` | `v=spf1 include:amazonses.com ~all` | — |
| CNAME | `rsend.mail` | `send.forge.rmta.net` | — |

## Server environment

Configure these in the **actual backend runtime's** environment/secrets manager:

- `RESEND_API_KEY`: a domain-restricted, sending-only Resend API key.
- `RESEND_FROM_EMAIL`: `Xylo <mail@mail.shashwataneja.com>`

Do not commit the API key, put it in a frontend `VITE_*` variable, or paste it into
client-side code. If it was exposed, revoke it and create a replacement. Do not use a
Vercel frontend environment variable as a substitute for a backend secret unless the
deployed server-side handler actually reads it.

## Code and current architectural boundary

- `backend/api/resend_mail.py`: server-side Resend HTTP adapter with input validation,
  timeout/error handling, and a non-secret provider message ID result.
- `backend/api/email_templates.py`: branded HTML and plain-text invoice reminder.
- `backend/api/invoice_mail.py`: orchestration helper. It is a library function, not
  an HTTP endpoint.
- `backend/tests/`: mocked provider/template/orchestration tests.
- `.github/workflows/resend-adapter-tests.yml`: unit test CI.

**Do not expose the orchestration helper as a route yet.** The repository's current
`backend/api/main.py` is an older FastAPI demo with in-memory user records and dummy
login tokens. It does not provide production-grade authentication or a trusted invoice
and customer data model. The documented target stack is Node.js/Express + Supabase Auth,
but the Resend adapter is currently Python. Wiring a public endpoint before resolving
that mismatch would risk an unauthenticated send path and arbitrary-recipient abuse.

Before adding a route, choose and implement the backend boundary: either (a) retain
FastAPI and validate Supabase access tokens, authorize business/invoice ownership against
trusted database records, rate-limit sends, and persist delivery attempts; or (b) port the
adapter into the intended Node.js/Express backend and use the same verified auth and
database checks. Do not accept arbitrary HTML or client-supplied recipient addresses.

## Verification checklist

- [x] Resend reports the sending domain verified.
- [x] Unit tests pass in CI (mocked provider; no email sent).
- [ ] Rotate any API key that was exposed outside the secrets manager.
- [ ] Configure the replacement key and sender in the chosen backend runtime.
- [ ] Implement an authenticated route using trusted invoice/customer records and rate limiting.
- [ ] Persist delivery attempts and provider IDs without storing secrets.
- [ ] Send one authenticated test email to a controlled inbox and verify the provider event.
