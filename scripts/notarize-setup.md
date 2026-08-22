# Notarization setup (one time)

Notarization removes the "cannot verify... malware" warning other Macs show
for the app. It is a one-time credential setup. After it, `release.sh`
notarizes and staples automatically.

## Steps

1. Create an app-specific password.
   - Sign in at https://account.apple.com
   - Go to "Sign-In and Security" > "App-Specific Passwords"
   - Add one named e.g. "MotionGraphics notary". Copy the password.

2. Save the credential to your login keychain (run once):

   ```sh
   xcrun notarytool store-credentials MG_NOTARY \
     --apple-id <your-apple-id-email> \
     --team-id <your-team-id> \
     --password <the-app-specific-password>
   ```

3. Build a release. It now notarizes and staples on its own:

   ```sh
   scripts/release.sh
   ```

## Notes

- Notarization uploads the app to Apple and waits for a pass. It usually
  takes 1 to 5 minutes.
- The profile name is `MG_NOTARY`. To use a different name, set
  `NOTARY_PROFILE=<name>` when running the script.
- Without the credential, `release.sh` still works. It signs but does not
  notarize, which is fine for your own Mac.
- To check a build is accepted by Gatekeeper:

  ```sh
  spctl -a -t open --context context:primary-signature -vv dist/MotionGraphics.dmg
  ```
