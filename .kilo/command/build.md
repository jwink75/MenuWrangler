---
description: Build, sign, and deploy the MenuWrangler application
---
# Build and Deploy

Build, sign, and deploy the MenuWrangler application.

## Usage
```bash
./scripts/build.sh
```

## What It Does
1. Cleans Dropbox conflict files and build artifacts
2. Builds the project using Xcode
3. Deep signs with Apple Development certificate
4. Strips quarantine attributes
5. Deploys to /Applications/MenuWrangler.app
6. Launches the app

## When to Use
- After making code changes to verify they compile
- Before testing new features
- After AG requests a build verification

## Notes
- The build script handles all signing and deployment
- Never build directly through Xcode — always use the script
- If build fails, check the error output and fix the code before retrying
