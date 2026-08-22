# CI release setup (one time)

The workflow `.github/workflows/release.yml` builds, signs, and notarizes
`MotionGraphics.zip` on a `macos-26` GitHub runner. It needs five repository
secrets.

## 1. Export the signing certificate

1. Open Keychain Access on the Mac that has the certificate.
2. Find your "Developer ID Application" certificate.
3. Expand it, select the certificate and its private key together.
4. Right-click > Export 2 items > save as `cert.p12` with a password.
5. Encode it:

   ```sh
   base64 -i cert.p12 | pbcopy
   ```

## 2. Add the repository secrets

```sh
gh secret set MACOS_CERT_P12_BASE64   # paste the base64 from above
gh secret set MACOS_CERT_PASSWORD     # the .p12 export password
gh secret set APPLE_ID                # your Apple ID email
gh secret set APPLE_TEAM_ID           # your team ID (in parentheses on the cert name)
gh secret set APPLE_APP_PASSWORD      # app-specific password (account.apple.com)
```

The app-specific password is the same kind used in
`scripts/notarize-setup.md`. You can reuse the one you made there.

## 3. Delete the local export

```sh
/bin/rm cert.p12
```

## Run it

- Push a tag: `git tag v0.1.0 && git push origin v0.1.0`. The zip lands on
  the GitHub release for that tag.
- Or trigger "Release" from the Actions tab. The zip lands in the run's
  artifacts.

## Notes

- macOS minutes bill at 10x on private repos. One run takes roughly 20 to
  40 minutes, most of it the notarization upload. Tag-only releases keep
  this cheap.
- The runner is arm64, which matches the arm64-only runtime downloads in
  `scripts/bundle-runtimes.sh`.
