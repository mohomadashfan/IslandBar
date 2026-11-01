# Releasing

## Automated (GitHub Actions)

1. Update `CFBundleShortVersionString` in `Support/Info.plist` and note the changes for the release.
2. Make sure CI on `main` is green.
3. Tag and push:

   ```sh
   git tag v0.2.0
   git push origin v0.2.0
   ```

4. The **Release** workflow runs the tests, builds a universal (arm64 + x86_64) app, and
   attaches `IslandBar-0.2.0.zip` and its SHA-256 checksum to a **draft** GitHub release.
5. Edit the draft notes and publish it.

The version comes from the tag. The build number is the commit count.

## What the artifacts are

CI has no signing credentials, so release artifacts are **ad-hoc signed and not notarized**.
Gatekeeper will block them on first launch; users need to choose *Open Anyway* (see
[BUILDING.md](BUILDING.md#signing-and-gatekeeper)). Say this plainly in the release notes.

## Developer ID signing and notarization (optional)

This requires an Apple Developer Program membership. It is done locally, so no credentials are
stored in the repository or in CI:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" UNIVERSAL=1 \
  scripts/package-release.sh 0.2.0

xcrun notarytool submit dist/IslandBar-0.2.0.zip --keychain-profile "islandbar-notary" --wait
xcrun stapler staple dist/IslandBar.app
ditto -c -k --keepParent dist/IslandBar.app dist/IslandBar-0.2.0.zip
```

With an identity set, the script signs with the hardened runtime and
`Support/IslandBar.entitlements`, which allows Apple Events. Create the notary profile once with
`xcrun notarytool store-credentials`.

Never commit certificates, `.p12` files, provisioning profiles or app-specific passwords;
`.gitignore` excludes the common file types.
