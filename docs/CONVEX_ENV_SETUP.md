# Setting Up CONVEX_DEPLOYMENT_URL Securely

## ⚠️ Important: Environment Variables in Shared Schemes

The `CONVEX_DEPLOYMENT_URL` should **NOT** be stored in the shared scheme file (`xcshareddata/xcschemes/`) because:
- It can be committed to git (even if in .gitignore, it might have been committed before)
- It exposes your Convex project URL
- Different developers might need different URLs (dev vs prod)

## ✅ Recommended: User-Specific Scheme

Use a **user-specific scheme** instead, which is automatically ignored by git:

### Option 1: Edit Scheme in Xcode (Recommended)

1. In Xcode, go to **Product → Scheme → Edit Scheme...**
2. Select **"Run"** in the left sidebar
3. Go to the **"Arguments"** tab
4. Under **"Environment Variables"**, add:
   - **Name:** `CONVEX_DEPLOYMENT_URL`
   - **Value:** `https://brilliant-iguana-281.convex.cloud`
   - ✅ Check the checkbox to enable it
5. Click **"Close"**

**Note:** This stores it in `xcuserdata/` which is already in `.gitignore`, so it won't be committed.

### Option 2: Use a .env File (Alternative)

1. Create a `.env` file in your project root:
   ```
   CONVEX_DEPLOYMENT_URL=https://brilliant-iguana-281.convex.cloud
   ```

2. Update `ConvexService.swift` to read from `.env`:
   ```swift
   private func getConvexDeploymentURL() -> String? {
       // Try .env file first
       if let envPath = Bundle.main.path(forResource: ".env", ofType: nil),
          let envContent = try? String(contentsOfFile: envPath) {
           for line in envContent.components(separatedBy: "\n") {
               let parts = line.components(separatedBy: "=")
               if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "CONVEX_DEPLOYMENT_URL" {
                   return parts[1].trimmingCharacters(in: .whitespaces)
               }
           }
       }
       
       // Fall back to environment variable
       if let url = ProcessInfo.processInfo.environment["CONVEX_DEPLOYMENT_URL"], !url.isEmpty {
           return url
       }
       
       return nil
   }
   ```

3. Make sure `.env` is in `.gitignore` (it already is)

### Option 3: UserDefaults (For Production)

For a production app, you might want users to configure it in settings:

1. Add a setting in `SettingsView`
2. Store it in `UserDefaultsManager`
3. Read from UserDefaults in `ConvexService`

## Current Status

I've removed the environment variable from the shared scheme file. You'll need to add it back using **Option 1** above (Edit Scheme in Xcode) so it's stored in your user-specific settings.

## Why This Matters

- **Security:** Keeps your deployment URL out of version control
- **Flexibility:** Different developers can use different URLs
- **Best Practice:** User-specific settings shouldn't be in shared files

## Quick Fix

Just re-add the environment variable in Xcode using the Edit Scheme dialog - it will automatically save to the user-specific location that's already gitignored.
