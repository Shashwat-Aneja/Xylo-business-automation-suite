Environment configuration

## Required practice
Configuration must enter the application through environment variables or the deployment platform, never through committed secrets.

## Categories
- database connection settings
- authentication configuration
- external API credentials
- application URLs
- runtime feature flags

## Safety
Commit an example configuration with placeholder values. Never commit real tokens, passwords, private keys, or production connection strings.