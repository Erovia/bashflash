# ![logo](bashflash_logo.png) bashflash
A small TUI script to flash firmware

---

## Usage

```bash
[erovia@pc]$ bash <(curl -s https://raw.githubusercontent.com/Erovia/bashflash/main/bashflash)
```

[![demo](https://asciinema.org/a/JNnFcVTM32sMUlXRBq2QFBKwk.svg)](https://asciinema.org/a/JNnFcVTM32sMUlXRBq2QFBKwk)

## Features

- Uses only Bash (v4+) and a few POSIX tools. (On macOS, please use the Bash from Homebrew.)
- No external dependencies besides the low-level flasher tools.
- No download/install necessary.
- Flashing/Multiflashing (similar to Toolbox's Auto-flash)
- `Doctor` menu for showing basic system info.
- Supported bootloaders and flashers:

| Bootloader      | Flasher             |
| ------------ | ---------------------- |
| Caterina     | `avrdude`              |
| Atmel DFU    | `dfu-programmer`       |
| DFU          | `dfu-util`             |
| WB32 DFU     | `wb32-dfu-updater_cli` |
| ISP/ASP      | `avrdude`              |
| UF2          | Not needed             |
| Massdrop     | `mdloader`             |
| QMK HID      | `avrdude`              |
| PJRC HalfKay | `avrdude`              |
