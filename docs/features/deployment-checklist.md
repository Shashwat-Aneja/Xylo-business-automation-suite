Deployment checklist

## Before deployment
- Run the available automated tests.
- Validate required environment variables.
- Confirm production API URLs.
- Verify database migrations are applied.
- Confirm secrets are not present in tracked files.
- Check the build output for warnings that indicate missing configuration.

## After deployment
Verify health endpoints, authentication, one read workflow, one write workflow, and error reporting before considering the release complete.