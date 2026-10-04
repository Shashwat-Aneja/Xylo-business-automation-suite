Report generation contract

## Purpose
Standardize how Xylo creates business reports from accounting and automation data.

## Pipeline
Data query -> validation -> aggregation -> presentation model -> renderer.

## Reliability requirements
- Fail explicitly when required source data is unavailable.
- Keep calculations independent from presentation formatting.
- Include the report generation timestamp.
- Preserve the selected reporting period and filters.
- Avoid embedding secrets or database credentials in generated artifacts.