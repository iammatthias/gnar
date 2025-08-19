# GitHub Actions Setup

This repository uses GitHub Actions to automatically deploy the GNAR landing page to Orbiter.

## Setup

1. **Create an API Key**: Visit [Orbiter API Keys](https://app.orbiter.host/api-keys) and create a new key with Admin permissions.

2. **Store the Secret**: In your GitHub repository:
   - Go to `Settings > Secrets and Variables > Actions`
   - Click "New repository secret"
   - Name: `ORBITER_API_KEY`
   - Value: Your API key

3. **Deploy**: The workflow will automatically trigger on pushes to the `main` branch.

## Configuration

The workflow is configured in `.github/workflows/deploy.yaml`:

- **Project name**: `gnar`
- **Build directory**: `./www` (contains the static HTML)
- **Build command**: No build needed - pure static HTML
- **Node version**: 20.x (minimum required)

## Manual Deployment

You can also deploy manually using the Orbiter CLI:

```bash
npx orbiter-cli update -d gnar ./www
```