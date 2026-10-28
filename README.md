
# TopBar OSD (Quickshell)

A custom top bar for **Quickshell** on Wayland (Hyprland / CachyOS / Arch).

## Features

- **Date & Time** with South African public holidays
- **System Volume** and **Microphone Volume** sliders (PipeWire)
- **Clipboard** preview (text + images) with hover preview and click-to-open
- **Bluetooth** status indicator
- **Phone (ADB)** status indicator
- **Auto webcam setup**:
  - Detects when an Android phone is connected via USB
  - Detects when OBS is running
  - Automatically opens **Open Camera** on the phone and switches to the front camera
  - Starts `scrcpy` headless as a v4l2 webcam (`/dev/video0`) for OBS
- **KEYS** button to toggle a keybindings overlay

## Requirements

### On the PC (Arch / CachyOS)

```bash
# Core
sudo pacman -S scrcpy android-tools v4l2loopback-dkms v4l-utils wl-clipboard python

# Kernel headers (needed for v4l2loopback DKMS)
sudo pacman -S linux-headers
# or if using CachyOS kernel:
# sudo pacman -S linux-cachyos-headers

# Load the v4l2loopback module
sudo modprobe v4l2loopback

# Make it load on boot (optional)
echo "v4l2loopback" | sudo tee /etc/modules-load.d/v4l2loopback.conf
```

### On the Phone

1. Enable **Developer Options** → **USB Debugging**
2. Install **Open Camera** (F-Droid or Play Store)
3. Open Open Camera once and grant camera permission

## Installation

1. Copy `topbar.qml` to your Quickshell config folder, for example:
   ```bash
   mkdir -p ~/.config/Quickshell/TopBarOSD
   cp topbar.qml ~/.config/Quickshell/TopBarOSD/
   ```

2. Launch it:
   ```bash
   quickshell -p ~/.config/Quickshell/TopBarOSD/topbar.qml
   ```

3. Toggle visibility by writing to the control file:
   ```bash
   echo 1 > /tmp/topbar_visible_$USER   # show
   echo 0 > /tmp/topbar_visible_$USER   # hide
   ```

## How the webcam auto-start works

When the bar becomes visible it checks:

1. Is an Android phone connected? (`adb devices`)
2. Is OBS running?

If both are true it:

1. Opens **Open Camera**
2. Taps the front-camera button (coordinates `500 1337`)
3. Starts `scrcpy --v4l2-sink=/dev/video0 --no-audio --no-control --no-window`

You can then add `/dev/video0` as a Video Capture Device in OBS.

## Notes

- The front-camera tap coordinates (`500 1337`) are specific to the phone resolution used during setup. Change them in `cameraOpenProcess` if needed.
- The bar only starts the camera/scrcpy sequence once per time it is opened.
- Bluetooth auto-connect runs in the background when the bar is shown.
