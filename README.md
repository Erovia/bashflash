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

| Bootloader      | Flasher               |
| ------------ | ------------------------ |
| Caterina     | `avrdude`                |
| Atmel DFU    | `dfu-programmer`         |
| DFU          | `dfu-util`               |
| WB32 DFU     | `wb32-dfu-updater_cli`   |
| ISP/ASP      | `avrdude`                |
| UF2          | `uf2conv.py` ([see below](https://github.com/Erovia/bashflash/edit/main/README.md#flashing-rp2040)) |
| Massdrop     | `mdloader`               |
| QMK HID      | `avrdude`                |
| PJRC HalfKay | `avrdude`                |


## Flashing RP2040

Flashing RP2040-based devices (Raspberry Pi Pico, SparkFun Pro Micro RP2040, Adafruit KB2040, etc) requires the `uf2conv.py` script from Microsoft.  
Bashflash looks at a number of directories for this script (such as local QMK installation directory, if it can find one) and tries to use that.  
Otherwise, you can quickly download the script from its [official repository](https://github.com/microsoft/uf2/tree/master/utils):
```bash
curl -LO https://raw.githubusercontent.com/microsoft/uf2/master/utils/uf2conv.py
curl -LO https://github.com/microsoft/uf2/blob/master/utils/uf2families.json
```
Note: You need both `uf2conv.py` **and** `uf2families.json`.
