# Gap Mesh - Emergency Decoy Mode Specification (Android Implementation)

## 1. Feature Overview
**Goal**: Create a plausible deniability mode. When the user triggers the "Panic Wipe," the app should clear all sensitive data and immediately transform into a fully functional calculator app.
**Behavior**:
- The app remains a calculator even across restarts.
- The app is silent (no background services, BLE, or Tor) while in this mode.
- The user can only return to the normal app by typing a secret PIN into the calculator and pressing `=`.

## 2. Core Mechanics

### A. Trigger (Panic Wipe)
- **Action**: Triple-tap on the main "Gap Mesh" header/logo in the main chat/home view.
- **Immediate Effect**:
  1. Calls existing `panicClearAllData()` (wipes DB, keys, shared prefs).
  2. Sets `isDecoyActive = true` in secure storage.
  3. Navigates immediately to `CalculatorActivity` (replacing the main stack).

### B. Decoy Mode (The Calculator)
- **UI**: Looks exactly like a standard system calculator (dark mode).
- **Functionality**: Must be a *working* calculator. Supports: `+`, `-`, `×`, `÷`, `%`, `±`, `.`.
- **Exit Mechanism**:
  - User types their secret PIN (e.g., `2580`).
  - User presses `=`.
  - If PIN matches: Clear decoy flag, restart app/navigate to Home.
  - If PIN fails: Perform standard calculation (e.g., show result of `2580` if no operator, or the math result).
- **Persistence**:
  - The `isDecoyActive` flag and the `decoyPIN` must survive the panic wipe.
  - **Critical**: Ensure the `panicClearAllData` routine does *not* delete the preference file containing the decoy flag and PIN.

### C. Service Suppression
- While `isDecoyActive` is true:
  - Do NOT start BLE advertising/scanning.
  - Do NOT start Tor or Nostr services.
  - The app should appear "dead" to the network.

## 3. Onboarding Flow Changes
Insert a new step for **Decoy PIN Setup** (Step 4 of 7).

**Flow**: Language → Identity → Mesh → **Decoy PIN** → EULA → Permissions.

**UI Requirements**:
1.  **Explanation**: "Stealth Mode: Triple-tap to wipe & hide. App becomes a real calculator."
2.  **PIN Generation**:
    - Show a randomly generated 4-digit PIN by default.
    - Button: "Generate New" (random).
    - Button: "Choose My Own" (allow 4-8 digits).
3.  **Mandatory Checkbox**: "I've memorized my PIN". Next button is disabled until checked.
4.  **Warning**: "This is the only way back. It cannot be recovered."

## 4. Settings Addition
Add a **"Decoy PIN"** row in the Privacy/Security section (after Panic Mode).
- **Action**: Opens a dialog/screen to update the PIN.
- **Fields**: New PIN, Confirm PIN.

## 5. Calculator Logic (Reference)
The calculator must maintain a `digitBuffer` string that tracks keys pressed *since the last operator or clear*.
- **Input `5`**: Display "5", Buffer "5"
- **Input `+`**: Display "5", Buffer cleared
- **Input `1`, `2`**: Display "12", Buffer "12"
- **Input `=`**:
  - Check if `Buffer == UserPIN`.
  - If yes: **Unlock App**.
  - If no: **Execute Math** (5 + 12 = 17).

## 6. Localization (Strings)
Ensure all new strings support English (`en`) and Farsi (`fa`).

### Onboarding Strings
| Key | English | Farsi |
|-----|---------|-------|
| `onboarding.decoy_title` | Stealth Mode | حالت مخفی |
| `onboarding.decoy_desc` | When you triple-tap to wipe all data, Gap Mesh instantly transforms into a calculator app. To anyone looking at your phone, it's just a calculator. | وقتی برای پاکسازی داده‌ها سه بار ضربه می‌زنید، گپ مش فوراً به یک ماشین‌حساب تبدیل می‌شود. برای هرکسی که به گوشی شما نگاه می‌کند، فقط یک ماشین‌حساب است. |
| `onboarding.decoy_how_title` | How it works | نحوه کار |
| `onboarding.decoy_how_wipe` | Triple-tap header to wipe & hide | سه‌بار ضربه روی سربرگ برای پاکسازی و مخفی‌سازی |
| `onboarding.decoy_how_calc` | App becomes a real calculator | برنامه به ماشین‌حساب واقعی تبدیل می‌شود |
| `onboarding.decoy_how_pin` | Enter your PIN + press = to return | پین خود را وارد کنید + مساوی بزنید تا برگردید |
| `onboarding.decoy_how_persist` | Persists across app restarts | پس از بسته شدن برنامه هم باقی می‌ماند |
| `onboarding.decoy_pin_label` | Set your recovery PIN | پین بازیابی خود را تنظیم کنید |
| `onboarding.decoy_pin_warning` | Remember this PIN! It's the only way back into Gap Mesh after a wipe. It cannot be recovered. | این پین را به خاطر بسپارید! تنها راه بازگشت به گپ مش پس از پاکسازی است. قابل بازیابی نیست. |
| `onboarding.decoy_memorized` | I've memorized my PIN | پین خود را حفظ کردم |
| `onboarding.decoy_generate_new` | Generate New | ساخت پین جدید |
| `onboarding.decoy_choose_own` | Choose My Own | انتخاب پین دلخواه |

### Settings Strings
| Key | English | Farsi |
|-----|---------|-------|
| `settings.decoy_pin_title` | Decoy PIN | پین ماشین‌حساب |
| `settings.decoy_pin_desc` | Change the PIN used to exit calculator mode | تغییر پین برای خروج از حالت ماشین‌حساب |
| `settings.decoy_pin_new` | New PIN | پین جدید |
| `settings.decoy_pin_confirm` | Confirm PIN | تایید پین |
| `settings.decoy_pin_mismatch` | PINs don't match | پین‌ها مطابقت ندارند |
| `settings.decoy_pin_saved` | PIN updated | پین به‌روز شد |

## 7. Android Specific Implementation Hints
- **Storage**: Use `EncryptedSharedPreferences` separate from the main app prefs (which get wiped). Name it something innocuous like `app_config_util` or `device_cache`.
- **Activity**: Create `CalculatorActivity`.
- **Manifest**: Ensure `CalculatorActivity` is not the launcher activity, but can be switched to dynamically or just routed to via `MainActivity` `onCreate` check:
  ```kotlin
  if (decoyManager.isDecoyActive()) {
      startActivity(Intent(this, CalculatorActivity::class.java))
      finish()
      return
  }
  ```
- **Back Button**: In Decoy Mode, the back button should exit the app (minimize), NOT go back to the chat view.
