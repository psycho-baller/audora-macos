# Convex Integration Setup

This document describes the Convex backend setup required for the Mac app's audio file upload functionality.

## Overview

The Mac app uploads audio files to Convex object storage when users click the "Generate" button. This happens before the note generation process begins.

## Required Convex Route

You need to create a Convex mutation that generates an upload URL for audio files.

### Mutation: `audio:generateUploadUrl`

**Location:** `convex/audio.ts` (or your preferred location)

**Code:**

```typescript
import { mutation } from "./_generated/server";

/**
 * Generates an upload URL for audio files.
 * This is called by the Mac app before uploading an audio file.
 * 
 * @returns A URL that can be used to upload a file via HTTP POST
 */
export const generateUploadUrl = mutation({
  args: {},
  handler: async (ctx) => {
    // Generate an upload URL using Convex storage
    const uploadUrl = await ctx.storage.generateUploadUrl();
    return uploadUrl;
  },
});
```

## Upload Flow

1. **Mac app calls mutation:** `client.mutation("audio:generateUploadUrl", with: [:])`
2. **Convex returns upload URL:** A temporary URL for uploading the file
3. **Mac app uploads file:** HTTP POST request to the upload URL with the audio file data
4. **Convex returns storage ID:** The response contains a `storageId` that can be used to reference the file later

## Response Format

The mutation should return a string URL that the Mac app can use for uploading.

After the file is uploaded via HTTP POST, Convex will return a response containing the storage ID. The Mac app expects one of these formats:

1. **JSON response:**
   ```json
   {
     "storageId": "abc123..."
   }
   ```

2. **Plain string response:**
   ```
   "abc123..."
   ```

## Storage ID Usage

Currently, the Mac app logs the storage ID but doesn't store it in the database (as per requirements - database schema updates are pending). Once the database schema is updated, you'll need to:

1. Create a mutation to store the storage ID with the meeting
2. Update the Mac app to call this mutation after successful upload

## Testing

To test the integration:

1. Set the `CONVEX_DEPLOYMENT_URL` environment variable in your Mac app
2. Record a meeting with audio
3. Click the "Generate" button
4. Check the console logs for upload status
5. Verify the file appears in Convex storage

## Environment Configuration

The Mac app reads the Convex deployment URL from:
- Environment variable: `CONVEX_DEPLOYMENT_URL`
- Future: UserDefaults or config file (TODO)

Set this in your Xcode scheme or environment configuration.

## Notes

- The upload happens asynchronously before note generation
- If the upload fails, note generation still proceeds (non-blocking)
- Audio files are typically `.m4a` format
- File sizes can vary significantly depending on meeting length
