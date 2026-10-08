# Signing and notarization

## Without an Apple Developer Program account

You may build, ad-hoc sign, package, and distribute a `.app` in a `.dmg`, and
publish it through a custom Homebrew tap. None of that requires paid membership.
There is no App Store submission in this pipeline.

Ad-hoc signing does **not** establish an identified developer and cannot be used
for notarization. A browser download is normally quarantined and Gatekeeper can
block first launch; a DMG or brew installation does not remove this. Document
Apple's per-app **Open Anyway** process for trusted downloads. Do not recommend
`spctl --master-disable`, `xattr -dr`, or Homebrew's `--no-quarantine`.

## For a normal download experience

1. **Membership** must be active (Apple lists US$99/year; a free account is not
   sufficient for Developer ID distribution/notarization).
2. Create a **Developer ID Application** certificate (not Apple Development or
   Mac App Store): request a CSR in Keychain Access → Certificate Assistant,
   create the certificate at developer.apple.com with that CSR, and install it on
   the Mac that generated the CSR so its private key appears beneath it.
3. Export **certificate + private key** as a password-protected `.p12` (exporting
   only the certificate cannot sign). Keep the key backed up and secure.
4. Configure the `release` environment secrets below.
5. The build signs nested Mutagen first, then the app, with hardened runtime and
   timestamp; packaging notarizes/staples each app, builds the DMGs, then
   signs/notarizes/staples the DMGs and validates stapling.
6. Hashes and Homebrew metadata are generated **after** signing/stapling. Partial
   credentials or signing failures stop the release.
7. Test a fresh, quarantined download on clean Macs.

## The signing identity string

`security find-identity -v -p codesigning` lists usable identities (certificate
**with** private key), for example:

```
  1) ABCDEF0123456789ABCDEF0123456789ABCDEF01 "Developer ID Application: Example Name (<TEAMID>)"
     1 valid identities found
```

`MACOS_CODESIGN_IDENTITY` is the **common name in the quotes**, without the quote
characters and **not** the SHA-1 hash:

```
Developer ID Application: Example Name (<TEAMID>)
```

- Keep the `(<TEAMID>)` suffix; it is part of the name.
- Do not use the SHA-1 hash. `codesign` happens to accept it, but the name is the
  intended value.
- An empty list, or an identity with no disclosure ▸ (no private key), cannot
  sign — install the certificate first.

## Exporting the `.p12` (and the two password prompts)

The `.p12` must contain the **certificate and its private key**. In Keychain
Access:

1. Select the **login** keychain (not System / System Roots, which are read-only).
2. Open the **My Certificates** category (not "Certificates", which hides the key).
3. Select `Developer ID Application: … (<TEAMID>)`; expand the ▸ to confirm the
   private key is nested beneath it.
4. Right-click → **Export "Developer ID Application: …"** → choose
   **Personal Information Exchange (.p12)**.

Two prompts appear, and they are **different secrets**:

| Prompt                                                  | Enter                                          | Becomes                                                     |
| ------------------------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------- |
| `kcproxy wants to export key` (login keychain password) | your **Mac account / login keychain** password | nothing stored — it only authorises reading the private key |
| "Enter a password to protect this item" + Verify        | a **new random** value you choose              | `MACOS_CERTIFICATE_PWD`                                     |

**`.p12` greyed out?** You are in the wrong category/keychain, or the key is
absent: switch from "Certificates" to **My Certificates**; ensure the certificate
is in the login keychain; confirm a private key is nested under it. Command-line
fallback (exports every identity in login as one `.p12`; `codesign` still selects
Developer ID by name):

```sh
security export -k ~/Library/Keychains/login.keychain-db \
  -t identities -f pkcs12 -o ~/Desktop/DeveloperID.p12
# then enter the random .p12 password when prompted
```

## Three passwords — do not confuse them

| Secret                  | Protects                              | Issued by                     | Used at                                       |
| ----------------------- | ------------------------------------- | ----------------------------- | --------------------------------------------- |
| `MACOS_CERTIFICATE_PWD` | the exported `.p12` file              | **you** — random              | `security import … -P …` on the runner        |
| `KEYCHAIN_PWD`          | the disposable runner keychain        | **you** — random              | `security create-keychain -p …` on the runner |
| `APPLE_APP_PASSWORD`    | your Apple ID login, for notarization | **Apple** (account.apple.com) | `notarytool submit … --password …`            |

The `.p12` password is local to the file and is never sent to Apple. Never reuse
the app-specific password as the `.p12` or keychain password. Generate the two
random values independently:

```sh
openssl rand -base64 32   # MACOS_CERTIFICATE_PWD
openssl rand -base64 24   # KEYCHAIN_PWD
```

## Release environment secrets (GitHub `release`)

All seven are scoped to the `release` environment, so only the tag-triggered
release job can read them. `MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PWD`, and
`KEYCHAIN_PWD` are **CI-only**; local packaging does not use them because the
certificate and key already live in the maintainer's keychain. For local
packaging, copy [release.env.example](release.env.example) to a git-ignored
`release.env` in the repository root.

| Secret                    | Value                                                          |
| ------------------------- | -------------------------------------------------------------- |
| `MACOS_CODESIGN_IDENTITY` | `Developer ID Application: Name (<TEAMID>)` (the CN, unquoted) |
| `MACOS_CERTIFICATE`       | base64 of the `.p12`, single line                              |
| `MACOS_CERTIFICATE_PWD`   | the `.p12` password set at export time                         |
| `KEYCHAIN_PWD`            | a separate random value                                        |
| `APPLE_ID`                | Apple account used for notarization                            |
| `APPLE_TEAM_ID`           | Developer Program team ID                                      |
| `APPLE_APP_PASSWORD`      | app-specific password, not the account password                |

From the project directory root run:

```sh
R=<owner>/symplast
base64 -i ~/Desktop/DeveloperID.p12 | tr -d '\n' > /tmp/cert.b64
gh secret set MACOS_CERTIFICATE --repo $R --env release --body "$(cat /tmp/cert.b64)"
rm -f /tmp/cert.b64 ~/Desktop/DeveloperID.p12
for s in MACOS_CODESIGN_IDENTITY MACOS_CERTIFICATE_PWD KEYCHAIN_PWD \
         APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD; do
  gh secret set "$s" --repo $R --env release
done
```

## Verify

`python3 scripts/verify-release.py 0.1.0 --notarized` mounts the DMGs read-only
and checks signatures, stapling, architecture slices, and resources without
launching the app or touching existing sync sessions.

References:

- https://developer.apple.com/programs/enroll/
- https://developer.apple.com/developer-id/
- https://support.apple.com/en-us/102445
