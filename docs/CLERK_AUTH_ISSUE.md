# Clerk Authentication Issue with ConvexMobile SDK

## Problem

Phase 3 implementation is complete, but authentication is failing with:
```
Uncaught Error: Not authenticated
```

## Root Cause

The ConvexMobile Swift SDK (v0.7.0) doesn't have built-in support for Clerk authentication. While we can:
- ✅ Sign in users with Clerk
- ✅ Fetch Clerk JWT tokens
- ❌ Pass those tokens to ConvexClient for backend requests

The SDK doesn't expose any API to set authentication tokens after initialization.

## Current State

### What Works
1. ✅ Clerk authentication (users can sign in)
2. ✅ Backend is configured for Clerk (`auth.config.ts`)
3. ✅ `ClerkAuthProvider` can fetch JWT tokens
4. ✅ Phase 3 code is implemented correctly

### What Doesn't Work
1. ❌ ConvexClient doesn't send JWT tokens with requests
2. ❌ Backend rejects requests with "Not authenticated"

## Investigation Results

### Package Dependencies
- `convex-swift` (v0.7.0) - Official SDK, no Clerk support
- `convex-swift-clerk` (branch: main) - Community package in dependencies
  - GitHub repo: `https://github.com/mellobirkan/convex-swift-clerk`
  - Commit: `2462d5fcad8ac6362febe5abc47a47366e5b5663`
  - **Issue**: Repo is not publicly accessible

### Comparison with Other Platforms
- **React/Web**: Has `ConvexProviderWithClerk` component
- **Auth0 (Swift)**: Has `ConvexClientWithAuth` with `Auth0Provider`
- **Clerk (Swift)**: No official support, custom implementation needed

## Solutions

### Option 1: Use convex-swift-clerk Package (Recommended if it works)
The package exists in dependencies but isn't imported/used. Try:

```swift
import ConvexSwiftClerk  // Or whatever module name it exports

// Initialize with Clerk auth
let convex = ConvexClientWithClerk(
    deploymentUrl: deploymentURL,
    clerkPublishableKey: clerkKey
)
```

**Action needed**: Check if this package provides working APIs

### Option 2: Implement Custom Auth Provider
Create a custom provider that:
1. Conforms to ConvexMobile's auth protocol (if it exists)
2. Fetches Clerk tokens
3. Injects them into requests

**Status**: ConvexMobile doesn't expose this protocol publicly

### Option 3: HTTP Wrapper (Workaround)
Create a wrapper that:
1. Intercepts ConvexClient requests
2. Adds `Authorization: Bearer <token>` headers
3. Forwards to Convex backend

**Pros**: Should work
**Cons**: Complex, bypasses SDK, may break updates

### Option 4: Wait for Official Support
Contact Convex team or contribute to SDK

## Immediate Next Steps

### Step 1: Check convex-swift-clerk Package
Since it's in dependencies, try:
1. Import the package: `import ConvexSwiftClerk` (or check actual module name)
2. Check if it exports `ConvexClientWithClerk` or similar
3. Test if it works with current setup

### Step 2: Create Clerk JWT Template
Ensure Clerk has a "convex" JWT template:
1. Go to Clerk Dashboard → JWT Templates
2. Create template named "convex"
3. Set `aud` claim to "convex"
4. Copy issuer URL

### Step 3: Verify Backend Config
Ensure `backend/convex/auth.config.ts` has correct issuer:
```typescript
{
  domain: "https://your-clerk-issuer-url.clerk.accounts.dev",
  applicationID: "convex",
}
```

## Files Modified for Phase 3

1. ✅ `audora/Models/Meeting.swift` - Added `convexConversationId`
2. ✅ `audora/Managers/RecordingSessionManager.swift` - Backend integration
3. ✅ `audora/ViewModels/MeetingViewModel.swift` - Pass title/calendarEventId
4. ✅ `audora/Services/ConvexService.swift` - Auth methods (incomplete)
5. ✅ `audora/Services/ClerkAuthProvider.swift` - Token fetching

## Testing Once Fixed

```bash
# 1. Start backend
cd backend && npx convex dev

# 2. Run app and start recording
# 3. Check console for:
#    ✅ "📝 Creating conversation in backend..."
#    ✅ "✅ Conversation created: <id>"
#    ✅ "📤 Processing transcript with backend..."
#    ✅ "✅ Backend processing complete"

# 4. Verify in Convex dashboard:
#    - New conversation record
#    - Transcript turns saved
#    - Facts extracted
```

## References

- ConvexMobile SDK: https://github.com/get-convex/convex-swift
- Clerk + Convex (Web): https://docs.convex.dev/auth/clerk
- Auth0 + Convex (Swift): https://github.com/get-convex/convex-swift-auth0
