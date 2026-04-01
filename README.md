# SoundShift 🚀

**SoundShift** is a minimalist, open-source audio control center for Windows and macOS. It allows you to route specific applications to different audio outputs with zero friction.

![SoundShift App](https://github.com/DevOpenMindset/audio_router_releases/raw/main/screenshots/app_main.png) _(Replace with actual URL or local path once pushed)_

## ✨ Key Features

- **🎯 Smart App Routing**: Force any app (browser, game, music player) to a specific output device (headset, speakers, monitor).
- **🌗 Native Look & Feel**: Beautiful, lightweight UI designed to feel native on both Windows 11 and macOS Sonoma.
- **🎨 Adaptive UI**: The application interface dynamically tints itself based on the dominant color of the active app's icon.
- **⚡ App Rules**: Automatically route your favorite apps as soon as they open. Set it once, forget it.
- **🔊 Auto-Ducking**: Automatically lower your background music when a voice call or specific app becomes active.
- **🏗 Multi-Profile**: Create and switch between entire audio routing configurations (e.g., "Gaming Mode", "Work Mode").
- **💨 Lightweight**: Built with Google's Flutter for high performance and low resource consumption.

## 📥 Installation

### Windows
1. Download the latest `SoundShift-Setup-Win.exe` from the [Releases](https://github.com/DevOpenMindset/audio_router_releases/releases) page.
2. Run the installer.
3. SoundShift will launch and sit in your system tray.

### macOS
1. Download the `SoundShift-MacOS.dmg` from the [Releases](https://github.com/DevOpenMindset/audio_router_releases/releases) page.
2. Drag and drop to your Applications folder.
3. Open SoundShift from your Applications (you may need to grant accessibility permissions for audio control).

## 🛠 For Developers

### Building from source
You need the Flutter SDK installed on your machine.

1. Clone the repository:
   ```bash
   git clone https://github.com/DevOpenMindset/audio_router.git
   cd audio_router
   ```
2. Get dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run -d windows # for Windows
   flutter run -d macos   # for macOS
   ```

## 🤝 Contributing

Contributions are what make the open-source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.

## ❤️ Support

If you find SoundShift useful, consider [buying me a coffee](https://www.buymeacoffee.com/openmindset) to support further development!
