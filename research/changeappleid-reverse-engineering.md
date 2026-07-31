# ChangeAppleID v1.9-1 — Reverse Engineering

> Source: `ChangeAppleID_1.9-1_Release.deb` from `https://xoainfo.com/cydia`
> Author: Nguyễn Quang Vũ (ienthach) — ienthach87@gmail.com
> Depends: firmware ≥ 9.0, RocketBootstrap, MobileSubstrate

## What It Does

**ChangeAppleID** is a credential manager that lets you store multiple Apple ID accounts and hot-swap between them. Instead of signing out and back in, it injects credentials directly into Apple's auth services at the system level — the App Store / iTunes instantly sees a different logged-in account.

## Architecture

```
┌──────────────────────────────────────────────┐
│ ChangeAppleID.app (GUI)                      │
│ ├── UITableView: list of stored accounts     │
│ ├── index.html: WebView form                │
│ │   └── Input: email|password|country|serial │
│ └── CPDistributedMessagingCenter IPC         │
├──────────────────────────────────────────────┤
│ LoginAppleID.dylib (arm64 + arm64e)          │
│ Targets 4 system processes:                  │
│   ├── com.apple.akd                          │
│   ├── com.apple.Preferences                  │
│   ├── com.apple.AppStore                     │
│   └── com.apple.itunesstored                 │
│                                              │
│ Key classes:                                 │
│   ChungThuc (Authentication)                 │
│   DataNetwork (socket + HTTP)                │
│   DeviceInfoHelper (ECID/IMEI/MEI/MAC)       │
│   Obfuscator (code obfuscation)              │
│   RNCryptor (AES-256 encryption)             │
│   CustomRoute (URL routing/MITM)             │
└──────────────────────────────────────────────┘
```

## How It Works — 4-Step Flow

### Step 1: Store Credentials

User opens the app, sees a WebView with form:
```
Textarea: abcd@email.com|12345678|US|F2LVB2B8JCLX
           ↑ email         ↑ pass  ↑ ISO ↑ serial
```

Credentials stored in encrypted format using **RNCryptor** (AES-256-CBC + HMAC, same as XoaInfo + KidsAutov4). The `viewForAppearance` class handles encryption/decryption:
- `loadData:withSettings:view:error:` — load from disk
- `decryptData:withSettings:encryptionKey:HMACKey:error:` — decrypt
- `loadView:withView:error:` — render in WebView

### Step 2: Select Account to Activate

App shows a `UITableView` listing all stored accounts. User taps one → app decrypts credentials → sends to dylib via **CPDistributedMessagingCenter** IPC.

### Step 3: Dylib Injects into Auth Services

`LoginAppleID.dylib` is loaded into 4 processes via MobileSubstrate:

| Process | Role | What's Hooked |
|---------|------|---------------|
| **akd** | AuthKit daemon — core Apple ID auth | `activeAccount`, `accountWithUniqueIdentifier:`, `_authKitPromptForCredentialsWithReason:` |
| **Preferences** | Settings → Apple ID section | Auth challenge handlers |
| **AppStore** | App Store app | `connection:willSendRequestForAuthenticationChallenge:` |
| **itunesstored** | iTunes Store daemon | StoreKit auth (SKCloudServiceController) |

The dylib uses **`class_replaceMethod`** (runtime injection) to override auth handlers:
- `connection:willSendRequestForAuthenticationChallenge:` — intercept auth challenge
- `connection:didReceiveAuthenticationChallenge:` — handle auth response
- `connectionShouldUseCredentialStorage:` — control credential storage
- `accountWithUniqueIdentifier:` — return swapped account
- `activeAccount` — return active account (swapped)

### Step 4: MITM the Auth Flow

When App Store or Settings tries to authenticate:
1. System calls `activeAccount` on akd → dylib returns the **swapped** account
2. System sends auth challenge → dylib intercepts via `connection:willSendRequestForAuthenticationChallenge:`
3. Dylib injects stored credentials (email + password) into the challenge response
4. Apple servers see the injected credentials → login succeeds
5. App Store now shows the **swapped** Apple ID's purchases/downloads

## Key Dylib Methods

### Authentication (ChungThuc)
```
authen                        — Core authentication logic
checkErrorLogin               — Handle login errors
cleanUpUnusedAccounts         — Remove stale accounts
_authKitPromptForCredentialsWithReason:error: — Intercept credential prompt
```

### Device Fingerprinting (DeviceInfoHelper)
Apple auth requires device info for trust score. The dylib collects:
```
deviceFullInfo                — Full device snapshot
ECID                          — Exclusive Chip ID
IMEI                          — IMEI number
MEID                          — Mobile Equipment ID
bluetoothMACAddress           — MAC address
randomIMEID                   — Generate random IMEI (for spoofing)
luhnCheck:                    — Validate IMEI checksum
```

### Encryption (RNCryptor)
```
decryptData:withSettings:encryptionKey:HMACKey:error:
unLoadView:withSettings:password:IV:encryptionSalt:HMACSalt:error:
decryptData:withEncryptionKey:HMACKey:error:
```

Settings structure:
```
{RNCryptorSettings:
  algorithm     = AES-256-CBC
  blockSize     = 16
  IVSize        = 16
  options       = 0
  HMACAlgorithm = SHA-256
  keySettings:  PBKDF2 (10k rounds)
  HMACKeySettings: PBKDF2}
```

### Network (DataNetwork)
```
postSocketWith:toDuongLink:   — POST to external server
POSTDataCFParameters:toURLPHP:completeHandler:failHandler:
socket:didConnectToHost:port:
socket:didReadData:withTag:
```

### Code Obfuscation
```
Obfuscator                    — String/method obfuscation
__PPIOS_DOUBLE_OBFUSCATION_GUARD__  — Double obfuscation guard
s45wjSGO, t9GVBVh3         — Obfuscated salt/keys
```

## Integration with XoaInfo Ecosystem

ChangeAppleID is part of the ienthach tool suite:

```
XoaInfo       → Device spoofing (model, IMEI, serial)
ChangeAppleID → Apple ID credential swap
sshChanger    → SSH host key rotation
PCAutoD       → PC automation
SearchPlaces  → Location search
```

**Combined attack flow:**
1. XoaInfo spoofs device identity (new serial, IMEI, UDID)
2. ChangeAppleID swaps Apple ID
3. App Store sees: new device + different account = clean slate
4. No link to previous purchases/downloads/account

## Comparison: ChangeAppleID vs Native Apple ID Switch

| Method | Time | Password Required | 2FA | App Data Lost |
|--------|------|-------------------|-----|---------------|
| **Settings → Sign Out** | 2-5 min | Yes | Yes | Some apps |
| **ChangeAppleID** | Instant | No (cached) | Bypassed | No |

## Security Implications

1. **Credential storage**: Encrypted with RNCryptor AES-256 on device, but decryption key is likely hardcoded in the binary
2. **MITM auth**: Dylib intercepts auth at the system level — no way for Apple to detect this from server side
3. **Anti-fraud bypass**: By rotating device identity (XoaInfo) + Apple ID (ChangeAppleID), the tool bypasses Apple's fraud detection that links accounts to devices
4. **No 2FA**: Auth intercept bypasses two-factor authentication since the dylib hooks post-2FA token exchange

## Files

| Path | Purpose |
|------|---------|
| `ChangeAppleID.app/ChangeAppleID` | GUI app (storyboard + table view) |
| `ChangeAppleID.app/index.html` | WebView credential input form |
| `LoginAppleID.dylib` | Credential injector (arm64+arm64e) |
| `LoginAppleID.plist` | Filter: akd, Preferences, AppStore, itunesstored |
