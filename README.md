<div align="center">
    <!-- <img src="https://github.com/user-attachments/assets/309577e8-94db-431f-b8df-a53a763b4c87" alt="Logo" width="80" height="80"> -->

<h1 align="center">audora</h3>

  <p align="center">
    The Free, Open-Source AI Communication Coach for Busy Professionals
    <br />
     <a href="https://github.com/psycho-baller/audora/releases/latest/download/audora.dmg">Download for MacOS 14+</a>
  </p>
</div>

## Releasing a New Version

Follow these steps to create a new release with auto-updates:

### Prerequisites

- Homebrew packages: `brew install create-dmg sparkle`
- Make scripts executable: `chmod +x scripts/update_version.sh scripts/build_release.sh`

### Release Process

1. **Update the version number:**

   ```bash
   # For bug fixes (1.0 → 1.0.1):
   ./scripts/update_version.sh patch

   # For new features (1.0 → 1.1):
   ./scripts/update_version.sh minor

   # For major changes (1.0 → 2.0):
   ./scripts/update_version.sh major

   # For custom version:
   ./scripts/update_version.sh custom 1.2.0
   ```

2. **Build the release:**

   ```bash
   ./scripts/build_release.sh
   ```

   This will:

   - Clean build the app in Release mode
   - Create a signed DMG file
   - Generate the appcast.xml for auto-updates

3. **Create GitHub Release:**

   - Go to [GitHub Releases](https://github.com/psycho-baller/audora/releases)
   - Click "Create a new release"
   - Tag: `v1.0.1` (match the version number)
   - Title: `audora v1.0.1`
   - Upload the DMG and zip files from `releases/` folder
   - Generate release notes

4. **Update appcast:**

   ```bash
   git add appcast.xml
   git commit -m "Update appcast for v1.0.1"
   git push
   ```
