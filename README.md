# Meal Coach Demo (SwiftUI, iOS 17+)

A local-first SwiftUI demo app with two tabs:
- `Today`: Health snapshot, meal photo analysis, one-shot next meal recommendation
- `Library`: Daily history, medical record transcript library, preferences, data export/delete

## Requirements
- Xcode 15+
- iOS 17+
- OpenAI API key (entered at runtime, stored securely in Keychain)
- HealthKit and Location permissions are optional but recommended for richer recommendations

## Run
1. Open `What to Eat.xcodeproj` in Xcode.
2. Select the `What to Eat` scheme and an iOS 17+ simulator/device.
3. Build and run.
4. Complete onboarding:
   - Intro disclaimer
   - HealthKit permission (read-only)
   - Location permission (When In Use)
   - Photos permission
   - Enter OpenAI API key on `API Key Setup`

## Before Publishing
- Set your own Apple Developer team in Xcode Signing & Capabilities.
- Replace the placeholder bundle identifiers (`com.example.whattoeat*`) with your own unique identifiers before archiving or App Store submission.

## API Key Handling
- The app never hardcodes any API key.
- API key is entered by user and stored in Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
- UI only shows masked form (`••••••••ABCD`).
- Key can be removed from onboarding/settings flow.

## Permissions Used
- `NSHealthShareUsageDescription`
- `NSLocationWhenInUseUsageDescription`
- `NSPhotoLibraryUsageDescription`

HealthKit entitlement file: `What to Eat/What to Eat.entitlements`

## OpenAI Integration
- Endpoint: `https://api.openai.com/v1/responses`
- Uses `Authorization: Bearer <KEY>` and `Content-Type: application/json`
- Uses structured JSON schema responses for:
  - Meal analysis
  - Medical record transcription
  - Next meal recommendation
- Response parsing concatenates output segments and validates JSON before decoding.
- If strict schema mode fails (e.g. compatibility issue), client retries with non-strict schema format and validates locally.

## Storage
- SwiftData entities:
  - `MealEntry`
  - `DailySummary`
  - `MedicalRecordEntry`
  - `UserPreferencesStore`
- All app data remains local on device.
- No iCloud sync and no external backend.

## Tests
Unit tests include:
1. Image resize max dimension check
2. JPEG data URL formatting
3. MealAnalysis JSON decoding
4. Daily summary aggregation logic
5. Recommendation JSON decoding
