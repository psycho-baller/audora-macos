# Convex SDK Setup Instructions

## Adding ConvexMobile SDK to Xcode Project

1. **Open your Xcode project**

2. **Navigate to Package Dependencies:**
   - Select your project in the navigator
   - Select your target (e.g., "audora")
   - Go to the "Package Dependencies" tab

3. **Add the Convex Swift Package:**
   - Click the "+" button
   - Enter the repository URL: `https://github.com/get-convex/convex-swift`
   - Choose the latest version (or a specific version tag)
   - Click "Add Package"
   - Select the "ConvexMobile" product
   - Click "Add Package"

4. **Verify Import:**
   - The `ConvexService.swift` file should now be able to import `ConvexMobile`
   - Build the project to verify there are no errors

## Environment Configuration

To configure the Convex deployment URL:

### Option 1: Environment Variable (Recommended for Development)

1. In Xcode, go to Product → Scheme → Edit Scheme...
2. Select "Run" in the left sidebar
3. Go to the "Arguments" tab
4. Under "Environment Variables", add:
   - Name: `CONVEX_DEPLOYMENT_URL`
   - Value: `https://your-deployment.convex.cloud`

### Option 2: UserDefaults (Future Implementation)

The `ConvexService` can be updated to read from UserDefaults or a config file. This would allow users to configure it in the app settings.

## Testing the Integration

1. Ensure `CONVEX_DEPLOYMENT_URL` is set
2. Record a meeting with audio
3. Click the "Generate" button
4. Check the console for:
   - `✅ Convex client initialized with URL: ...`
   - `📤 Uploading audio file to Convex: ...`
   - `✅ Audio file uploaded successfully. Storage ID: ...`

## Troubleshooting

- **"Convex client is not initialized"**: Check that `CONVEX_DEPLOYMENT_URL` is set correctly
- **"Failed to generate upload URL"**: Verify the Convex mutation `audio:generateUploadUrl` exists
- **Build errors**: Ensure the ConvexMobile package is properly added and linked to your target
