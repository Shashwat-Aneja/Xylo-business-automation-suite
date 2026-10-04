Invoice processing flow

## Purpose
Define the processing contract for invoice ingestion so parsing, normalization, and accounting remain separate concerns.

## Flow
1. Accept the source document.
2. Extract raw text and preserve the original input metadata.
3. Normalize dates, currency symbols, invoice identifiers, supplier names, and totals.
4. Validate required fields before creating an accounting record.
5. Return structured validation errors instead of silently dropping fields.

## Required fields
- invoice number
- invoice date
- supplier
- currency
- total amount

## Design rule
Parsing should never mutate accounting state directly. The adapter layer should translate parsed data into the accounting engine's input model.