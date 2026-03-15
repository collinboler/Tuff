# Tuff

A competitive screen time tracking iOS app that gamifies reducing phone usage through friend leagues, betting, and high-friction blocking.

## Architecture

- **SwiftUI** with MVVM pattern
- **iOS 17+** (Swift Charts, modern SwiftUI APIs)
- **Apple Screen Time APIs**: FamilyControls, DeviceActivity, ManagedSettings

## Project Structure

```
Tuff/
├── Tuff/                              # Main app target
│   ├── App/
│   │   ├── TuffApp.swift              # App entry point + authorization
│   │   └── ContentView.swift          # Root tab navigation
│   ├── Theme/
│   │   └── Theme.swift                # Colors, fonts, reusable components
│   ├── Models/
│   │   ├── User.swift                 # User & LeagueMember models
│   │   ├── League.swift               # League & history models
│   │   └── ScreenTimeData.swift       # Screen time data models
│   ├── Services/
│   │   ├── ScreenTimeManager.swift    # FamilyControls/DeviceActivity integration
│   │   └── NotificationManager.swift  # Push notification handling
│   ├── ViewModels/
│   │   ├── HomeViewModel.swift
│   │   ├── StatsViewModel.swift
│   │   └── ProfileViewModel.swift
│   ├── Views/
│   │   ├── Home/                      # Home screen (carousel, leagues)
│   │   ├── League/                    # League detail, leaderboard, create
│   │   ├── Profile/                   # Profile & league history
│   │   ├── Stats/                     # Charts & streak tracking
│   │   └── Components/               # Reusable UI components
│   └── Assets.xcassets/
├── TuffDeviceActivity/                # DeviceActivity Monitor extension
├── TuffShieldConfiguration/           # Shield UI customization extension
└── project.yml                        # XcodeGen project specification
```

## Setup

### Option A: XcodeGen (Recommended)

1. Install XcodeGen:
   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:
   ```bash
   cd Tuff
   xcodegen generate
   ```

3. Open `Tuff.xcodeproj` in Xcode

4. Set your Development Team in project settings

5. Build and run on a physical device (Screen Time APIs require a real device)

### Firebase

- `GoogleService-Info.plist` is in the repo root and is added to the **Tuff** target (copy bundle resources).
- Firebase is initialized in `TuffApp` via `AppDelegate` and `FirebaseApp.configure()`.
- **Linking (per [Firebase iOS setup](https://firebase.google.com/docs/ios/setup)):** Add the SDK via **File → Add Package Dependencies** → `https://github.com/firebase/firebase-ios-sdk`. When choosing libraries, add **FirebaseCore** (and FirebaseAuth, FirebaseFirestore if needed) and set **Add to Target** to **Tuff**. The **Tuff** target has **Other Linker Flags** `-ObjC` set (required by Firebase).
- **If you still see "No such module 'FirebaseCore'":**
  1. In Xcode: **File → Packages → Reset Package Caches**.
  2. **Product → Clean Build Folder** (⇧⌘K).
  3. Quit Xcode, delete DerivedData for this project:  
     `rm -rf ~/Library/Developer/Xcode/DerivedData/Tuff-*`
  4. Reopen the project and build again (⌘B).

### Option B: Manual Xcode Setup

1. Open Xcode → File → New → Project → iOS App
2. Product Name: **Tuff**, Interface: **SwiftUI**, Language: **Swift**
3. Replace the generated files with the files from `Tuff/`
4. Add entitlements:
   - Select the Tuff target → Signing & Capabilities
   - Add "Family Controls" capability
5. Add extension targets:
   - File → New → Target → **Device Activity Monitor Extension** (name: TuffDeviceActivity)
   - File → New → Target → **Shield Configuration Extension** (name: TuffShieldConfiguration)
   - Replace generated files with those from `TuffDeviceActivity/` and `TuffShieldConfiguration/`
6. Build and run

## Apple Screen Time APIs Used

| Framework | Purpose |
|-----------|---------|
| **FamilyControls** | Request authorization to access screen time data |
| **DeviceActivity** | Monitor daily usage, set thresholds, track intervals |
| **ManagedSettings** | Block/shield apps, enforce restrictions |
| **ManagedSettingsUI** | Customize the shield shown on blocked apps |

### Key Flows

**App Blocking (Friend 2FA):**
1. User selects apps to block via `FamilyActivityPicker`
2. `ManagedSettingsStore` applies shields to those apps
3. When blocked app is opened, `ShieldConfigurationExtension` shows custom UI
4. Friend sends 2FA code → shields are removed

**Activity Monitoring:**
1. `DeviceActivityCenter` starts daily monitoring schedule
2. `DeviceActivityMonitor` extension tracks usage in the background
3. Thresholds trigger notifications and shield activation

## Features

- **Leagues**: Create competitive groups, set buy-ins, track rankings
- **Friend 2FA Blocking**: Apps stay locked until a friend sends you a code
- **Custom Challenges**: Complete productive tasks to earn screen time
- **Live Leaderboards**: Real-time rankings within each league
- **Stats & Charts**: 7-day / 30-day screen time visualization with Swift Charts
- **Streak Tracking**: Consecutive days under your screen time goal
- **Push Notifications**: League alerts, daily recaps, streak reminders
- **Payout System**: Winner-takes-all or tiered payouts

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Physical device (Screen Time APIs don't work in Simulator)
- Apple Developer account with Family Controls entitlement

## Applying for Family Controls Entitlement

The Screen Time APIs require special entitlement approval from Apple:

1. Go to [developer.apple.com](https://developer.apple.com)
2. Navigate to Account → Certificates, Identifiers & Profiles → Identifiers
3. Select your App ID → Enable "Family Controls"
4. Submit the request form explaining your use case
5. Apple typically approves within 1–2 weeks
