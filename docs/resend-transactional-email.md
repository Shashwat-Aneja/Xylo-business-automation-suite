# Resend transactional email setup

This integration keeps Resend credentials on the server. Never put `RESEND_API_KEY`
in HTML, browser JavaScript, a `VITE_*` variable, or a committed environment file.

## Current setup status

- Sending domain created in Resend: `mail.shashwataneja.com`
- Region: `ap-northeast-1`
- Open/click tracking: disabled
- TLS: enforced
- Sending API key: created with sending-only permission and restricted to this domain
- Domain verification: pending DNS configuration
- Sender identity after verification: `Xylo <mail@mail.shashwataneja.com>`

## DNS records

Add these records at the DNS provider authoritative for `shashwataneja.com`.
Because this is a subdomain, enter the record names exactly as your DNS dashboard
expects; some dashboards append the zone name automatically. Do not add duplicate
SPF TXT records at the same hostname.

| Type | Name / Host | Value / Target | Priority |
|---|---|---|---:|
| TXT | `resend._domainkey.mail` | `p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC4ytpiAzD+kdYUBDlh93+qxp/Z8S0UFForzeJ9vuazjttj/UZnGmc3KNnWGj6bp82W2u60VxIPQARevgRypTcrvSwxq/Ae4QF/6aWiRjwW2uJnahqnIkBwfDa16wmQWqH8JQ/lilKQo0vXsitwJZQgV98QLaYyaTp8maNpal5K0wIDAQAB` | — |
| MX | `send.mail` | `feedback-smtp.ap-northeast-1.amazonses.com` | 10 |
| TXT | `send.mail` | `v=spf1 include:amazonses.com ~all` | — |
| CNAME | `rsend.mail` | `send.forge.rmta.net` | — |

TTL: provider default / Auto. After adding DNS records, trigger domain verification in
Resend and wait until the domain is verified.

## Server environment

Configure these in the backend runtime's environment/secrets manager:

- `RESEND_API_KEY`: the domain-restricted sending-only API key created in Resend.
- `RESEND_FROM_EMAIL`: `Xylo <mail@mail.shashwataneja.com>`

Do not commit the API key or paste it into client-side code. If it is exposed, revoke it
and create a replacement.

## Code

`backend/api/resend_mail.py` contains the provider adapter. It validates basic input,
uses a bounded HTTP timeout, sends the API key only in the server-side Authorization
header, and returns only the provider message ID. Unit tests live in
`backend/tests/test_resend_mail.py`.

The adapter is not an unauthenticated public send endpoint. Before connecting it to
invoice reminders or other user-triggered actions, the caller must authenticate the
user, authorize access to the relevant business/invoice, resolve recipient details from
trusted records, rate-limit requests, and record delivery outcomes. Do not accept
arbitrary HTML or arbitrary recipients from unauthenticated clients.

## Verification checklist

- [ ] DNS records published and visible publicly.
- [ ] Resend domain status is verified.
- [ ] Server environment variables configured outside source control.
- [ ] Unit tests pass in CI.
- [ ] Authenticated, authorized test flow sends one email to a controlled test inbox.
- [ ] Resend delivery event/log confirms delivery; no API key appears in logs.
