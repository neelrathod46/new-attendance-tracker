# Manual Flutter & Android Setup Guide (Targeting `/mnt/work`)

This document provides step-by-step instructions to manually install Flutter, minimal Android Command-Line Tools, and configure USB debugging so that heavy files, SDKs, and build caches stay strictly on `/mnt/work`.

---

## Prerequisites & Disk Check
Check available space on `/mnt/work`:
```bash
df -h /mnt/work
```
*(Ensure you have at least 2.5–3 GB free).*

---

## Step 1: Install OpenJDK 17 and ADB
Flutter and Gradle need Java 17, and ADB is needed to communicate with your phone:
```bash
sudo apt update
sudo apt install -y openjdk-17-jdk adb
```

---

## Step 2: Create Tool Directories on `/mnt/work`
```bash
mkdir -p /mnt/work/tools/flutter
mkdir -p /mnt/work/tools/android-sdk/cmdline-tools
mkdir -p /mnt/work/tools/.pub-cache
mkdir -p /mnt/work/tools/.gradle/caches
```

---

## Step 3: Setup Symlinks (Keeps OS partition clean)
This ensures Flutter packages and Gradle cache files write directly to `/mnt/work` instead of `~`:

```bash
# 1. Pub Cache symlink
rm -rf ~/.pub-cache
ln -s /mnt/work/tools/.pub-cache ~/.pub-cache

# 2. Gradle Cache symlink
mkdir -p ~/.gradle
rm -rf ~/.gradle/caches
ln -s /mnt/work/tools/.gradle/caches ~/.gradle/caches

# 3. Binaries symlink (so flutter and dart are immediately available)
mkdir -p ~/.local/bin
ln -sf /mnt/work/tools/flutter/bin/flutter ~/.local/bin/flutter
ln -sf /mnt/work/tools/flutter/bin/dart ~/.local/bin/dart
```

---

## Step 4: Download Flutter SDK
Clone Flutter directly into `/mnt/work/tools/flutter` using a shallow clone (`--depth 1`) to save disk space:
```bash
git clone https://github.com/flutter/flutter.git -b stable --depth 1 /mnt/work/tools/flutter
```

---

## Step 5: Download Minimal Android Command-Line Tools
Download Google's official command-line tools (no heavy Android Studio IDE):
```bash
cd /mnt/work/tools/android-sdk/cmdline-tools
curl -fLo cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip -q cmdline-tools.zip
mv cmdline-tools latest
rm cmdline-tools.zip
```

---

## Step 6: Configure `~/.bashrc`
Open `~/.bashrc` in your preferred editor (e.g., `nano ~/.bashrc` or VS Code) and append these lines at the bottom:

```bash
# Java setup
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"

# Flutter & Android SDK on /mnt/work
export ANDROID_HOME="/mnt/work/tools/android-sdk"
export ANDROID_SDK_ROOT="/mnt/work/tools/android-sdk"
export PUB_CACHE="/mnt/work/tools/.pub-cache"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
```

Reload your environment:
```bash
source ~/.bashrc
```

---

## Step 7: Install Android Platform & Build Tools
Now use `sdkmanager` to install only the essential components required to compile Flutter APKs:
```bash
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
yes | sdkmanager --licenses
```

Tell Flutter where the Android SDK lives and accept the Flutter Android licenses:
```bash
flutter config --android-sdk /mnt/work/tools/android-sdk
yes | flutter doctor --android-licenses
```

Verify the installation:
```bash
flutter doctor
```

---

## Step 8: Connect Your Android Phone via USB

1. **Enable Developer Options**:
   - On your phone, go to **Settings > About Phone**.
   - Tap **Build Number** 7 times continuously until it says *"You are now a developer!"*.

2. **Enable USB Debugging**:
   - Go to **Settings > System > Developer Options** (or search for Developer Options).
   - Turn on **USB Debugging**.

3. **Authorize Laptop**:
   - Connect the phone to your laptop using a USB cable.
   - Run in terminal:
     ```bash
     adb devices
     ```
   - Look at your phone screen: a pop-up dialog will ask *"Allow USB debugging?"*.
   - Check **Always allow from this computer** and tap **Allow**.
   - Re-run `adb devices`; your phone should now show as `device`:
     ```text
     List of devices attached
     XXXXXXXXXX    device
     ```

4. **Verify Flutter Sees Your Phone**:
   ```bash
   flutter devices
   ```

5. **Run the App Directly on Your Phone**:
   ```bash
   cd /mnt/work/Projects/attendance
   flutter run
   ```
