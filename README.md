# Meal Coach Demo (SwiftUI, iOS 17+)

A local-first SwiftUI demo app with two tabs:
- `Today`: Health snapshot, meal photo analysis, one-shot next meal recommendation
- `My Data`: Daily history, health status records, provider setup, preferences, and local data management

## UI Screenshots

### Today Dashboard
<img src="activity_health_dynamic_tracking.PNG" alt="Today dashboard" width="320">

The `Today` tab is the main daily workflow. It combines a 7-day progress view, meal logging shortcuts, one-shot next meal recommendation, and a live health snapshot for sleep, energy, exercise, steps, weight, and body fat.

### Progress And Trend View
<img src="history_diagram.PNG" alt="Progress and trend view" width="320">

This view highlights streak tracking and the recent estimated energy balance chart, giving users a quick read on logging consistency and daily calorie balance trends.

### My Data Hub
<img src="Health_status_input_tracking.PNG" alt="My Data hub" width="320">

The `My Data` tab centralizes daily history, health status entries, and settings such as access management, API key setup, language, and data management.

### API Key Setup
<img src="Support_chatgpt_n_Qwen.PNG" alt="API key setup" width="320">

`API Key Setup` lets users switch between OpenAI and Qwen, save one provider key securely in Keychain, update the stored key, or remove it when needed.

### Language Settings
<img src="Support_english_n_chinese.PNG" alt="Language settings" width="320">

The `Language` screen switches both the app UI text and AI response language between English and Simplified Chinese.

## Requirements
- Xcode 15+
- iOS 17+
- OpenAI or Qwen API key for AI features (entered at runtime, stored securely in Keychain)
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
   - Enter an OpenAI or Qwen API key on `API Key Setup`

## Before Publishing
- Set your own Apple Developer team in Xcode Signing & Capabilities.
- Replace the placeholder bundle identifiers (`com.example.whattoeat*`) with your own unique identifiers before archiving or App Store submission.

## API Key Handling
- The app never hardcodes any provider API key.
- API key is entered by user and stored in Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
- Only one provider key is stored at a time; saving a new OpenAI or Qwen key replaces the other provider key.
- UI only shows masked form (`••••••••ABCD`).
- Key can be removed from onboarding/settings flow.

## Permissions Used
- `NSHealthShareUsageDescription`
- `NSLocationWhenInUseUsageDescription`
- `NSPhotoLibraryUsageDescription`

HealthKit entitlement file: `What to Eat/What to Eat.entitlements`

## AI Provider Integration
- OpenAI endpoint: `https://api.openai.com/v1/responses`
- Qwen endpoint: `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`
- Uses `Authorization: Bearer <KEY>` and `Content-Type: application/json`
- Uses structured JSON schema responses for:
  - Meal analysis
  - Medical record transcription
  - Next meal recommendation
- Response parsing validates JSON before decoding.
- OpenAI retries with non-strict schema format if strict schema mode fails.
- Qwen retries with a stricter JSON-only prompt if the first response does not validate.

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
