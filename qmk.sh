#!/usr/bin/env bash
VERSION="0.0.1"
MAINTAINER="Erovia"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
#################################################
#
#    TOOLS
#
#################################################
DFU_UTIL=$(command -v dfu-util 2>&1)
DFU_PROGRAMMER=$(command -v dfu-programmer 2>&1)
AVRDUDE=$(command -v avrdude 2>&1)

check_dfu_util_version() {
	echo $("$DFU_UTIL" -V | awk '/^dfu-util/ {print $2}')
}
check_dfu_programmer_version() {
	echo $("$DFU_PROGRAMMER" --version 2>&1 | awk '/^dfu-programmer/ {print $2}')
}
check_avrdude_version() {
	echo $("$AVRDUDE" 2>&1 | awk '/^avrdude version/ {print $3}' | tr -d ',')
}
#################################################
#
#    BOOTLOADERS
#
#################################################
declare -A BOOTLOADERS
BOOTLOADERS["03eb:2fef"]="atmel-dfu atmega16u2"
BOOTLOADERS["03eb:2ff0"]="atmel-dfu atmega32u2"
BOOTLOADERS["03eb:2ff3"]="atmel-dfu atmega16u4"
BOOTLOADERS["03eb:2ff4"]="atmel-dfu atmega32u4"
BOOTLOADERS["03eb:2ff9"]="atmel-dfu at90usb64"
BOOTLOADERS["03eb:2ffa"]="atmel-dfu at90usb162"
BOOTLOADERS["03eb:2ffb"]="atmel-dfu at90usb128"

# pid.codes shared PID
BOOTLOADERS["1209:2302"]="caterina atmega32u4" # Keyboardio Atreus 2 Bootloader
# Spark Fun Electronics
BOOTLOADERS["1b4f:9203"]="caterina atmega32u4" # Pro Micro 3V3/8MHz
BOOTLOADERS["1b4f:9205"]="caterina atmega32u4" # Pro Micro 5V/16MHz
BOOTLOADERS["1b4f:9207"]="caterina atmega32u4" # LilyPad 3V3/8MHz (and some Pro Micro clones)
# Pololu Electronics
BOOTLOADERS["1ffb:0101"]="caterina atmega32u4" # A-Star 32U4
# Arduino SA
BOOTLOADERS["2341:0036"]="caterina atmega32u4" # Leonardo
BOOTLOADERS["2341:0037"]="caterina atmega32u4" # Micro
# Adafruit Industries LLC
BOOTLOADERS["239a:000c"]="caterina atmega32u4" # Feather 32U4
BOOTLOADERS["239a:000d"]="caterina atmega32u4" # ItsyBitsy 32U4 3V3/8MHz
BOOTLOADERS["239a:000e"]="caterina atmega32u4" # ItsyBitsy 32U4 5V/16MHz
# dog hunter AG
BOOTLOADERS["2a03:0036"]="caterina atmega32u4" # Leonardo
BOOTLOADERS["2a03:0037"]="caterina atmega32u4" # Micro

bootloader=""
mcu=""
firmware=""
#################################################
#
#    COLOURS
#
#################################################
DEFAULT="\e[0m"
RED="\e[31m"
BORDER="\e[30;41m"
BOLD_BLUE="\e[1;34m"
#################################################
#
#    POSITIONS
#
#################################################
FIRST_LINE="\e[H"
#LAST_LINE="\e
TEXT_START="\e[3H"
scroll_position=0
active_item=0
#################################################
#
#    MENUS
#
#################################################
declare -a MAIN_MENU
MAIN_MENU[0]="Flash"
MAIN_MENU[1]="Doctor\n"
MAIN_MENU[2]="Quit"
MAIN_MENU_CONTENT="Super simple flashing TUI for QMK"
declare -a FLASH_MENU
FLASH_MENU[0]="Firmware\n"
FLASH_MENU[1]="Back"
FLASH_MENU_CONTENT="Flashing stuff will go here..."
declare -a FIRMWARE_MENU
FIRMWARE_MENU[0]="Back"
FIRMWARE_MENU[1]=".."
FIRMWARE_MENU_CONTENT="Select the firmware you'd like to flash:"
declare -a DOCTOR_MENU
DOCTOR_MENU[0]="Back"
DOCTOR_MENU_CONTENT=""

# Stack implementation
# https://stackoverflow.com/a/61476245
peek() { local -n "stack=$1"; printf %s\\n "${stack[-1]}"; }
push() { local -n "stack=$1"; shift; stack+=("$@"); }
pop() { peek "$1"; unset "$1[-1]"; }

menu_housekeeping() {
	current_menu_name="$(echo $(peek 'menu_stack')_MENU | tr '[:lower:]' '[:upper:]')"
	declare -ng "current_menu=$current_menu_name"
	current_menu_length="${#current_menu[@]}"
	current_menu_content_name="${current_menu_name}_CONTENT"
	declare -ng current_menu_content="$current_menu_content_name"
}
enter_menu() {
	push "menu_stack" "$1"
	push "scroll_stack" "${scroll_position} ${active_item}"
	scroll_position=0
	active_item=0
	menu_housekeeping
}
exit_menu() {
	pop "menu_stack" &>/dev/null
	read -r scroll_position active_item < <(pop "scroll_stack")
	menu_housekeeping
}

clear_formatting() {
	# Clear text formatting and newlines
	echo "$1" | sed 's/\\e\[[0-9;]*m\|\\n//g'
}

enter_menu "main"
#################################################
#
#    TUI stuff
#
#################################################
setup_terminal() {
	# Setup the terminal for the TUI.
	# '\e[?1049h': Use alternative screen buffer.
	# '\e[?7l':    Disable line wrapping.
	# '\e[?25l':   Hide the cursor.
	# '\e[2J':     Clear the screen.
	# '\e[1;Nr':   Limit scrolling to scrolling area.
	#              Also sets cursor to (0,0).
	printf "\e[?1049h\e[?7l\e[?25l\e[2J\e[2;%sr" "$((LINES-1))"
	# printf '\e[?1049h\e[?7l\e[?25l\e[2J\e[1;%sr\e[2;%ss' "$max_items" "$((COLUMNS-1))"
	# printf '\e[?1049h\e[?7l\e[?25l\e[2J'

	# Hide echoing of user input
	stty -echo
}

reset_terminal() {
	# Reset the terminal to a useable state (undo all changes).
	# '\e[?7h':   Re-enable line wrapping.
	# '\e[?25h':  Unhide the cursor.
	# '\e[2J':    Clear the terminal.
	# '\e[;r':    Set the scroll region to its default value.
	#             Also sets cursor to (0,0).
	# '\e[?1049l: Restore main screen buffer.
	printf '\e[?7h\e[?25h\e[2J\e[;r\e[?1049l'

	# Show user input.
	stty echo
}

get_term_size() {
	# Get terminal size ('stty' is POSIX and always available).
	# This can't be done reliably across all bash versions in pure bash.
	read -r LINES COLUMNS < <(stty size)

	((max_items=LINES-6))
}

clear_screen() {
	printf '\e[2J\e[H'
}

title_line() {
	# '\e[%sH':    Move cursor to bottom of the terminal.
	# '\e[30;41m': Set foreground and background colors.
	# '%*s':       Insert enough spaces to fill the screen width.
	#              This sets the background color to the whole line
	#              and fixes issues in 'screen' where '\e[K' doesn't work.
	# '\r':        Move cursor back to column 0 (was at EOL due to above).
	# '\e[m':      Reset text formatting.
	# '\e[H\e[K':  Clear line below status_line.
	# '\e8':       Restore cursor position.
	#              This is more widely supported than '\e[u'.
	#printf '\e[%sH\e[30;41m%*s\r%s %s%s\e[m\e[%sH\e[K\e8' \
	printf "${FIRST_LINE}\r${BORDER}%*s\r%s v${VERSION} by ${MAINTAINER}\e[0m" \
		"$COLUMNS" "" \
		"qmk.sh"
}

status_line() {
	# '\e[%sH':    Move cursor to bottom of the terminal.
	# '\e[30;41m': Set foreground and background colors.
	# '%*s':       Insert enough spaces to fill the screen width.
	#              This sets the background color to the whole line
	#              and fixes issues in 'screen' where '\e[K' doesn't work.
	# '\r':        Move cursor back to column 0 (was at EOL due to above).
	# '\e[m':      Reset text formatting.
	# '\e[H\e[K':  Clear line below status_line.
	# '\e8':       Restore cursor position.
	#              This is more widely supported than '\e[u'.
	#printf '\e[%sH\e[30;41m%*s\r%s %s%s\e[m\e[%sH\e[K\e8' \
	# printf '\e[%sH\e[30;41m%*s\r%s\e[%s;%sH%s\e[m' \
	printf "\e[${LINES}H${BORDER}%*s\r%s\e[%s;%sH%s${DEFAULT}" \
		"$COLUMNS" "" \
		"Move: UP/DOWN; Enter: ENTER; Back: Q" \
		"$LINES" "$((COLUMNS-${#DEBUG}))" "$DEBUG"
		#"$LINES" "hello" \
}

side_lines() {
	start=2
	end=$((LINES))
	for ((line = 2; line < $LINES; line++)); do
		# \e%sH : Move to the second line
		# \e[30;40m : Set black fg and red bg
		# %s : Print a single space
		# \e[%s;${COLUMNS}H : Move to the last column in the same line
		# %s : Print a single space
		printf "\e[%sH\e[30;41m%s\e[%s;${COLUMNS}H%s" \
			"$line" \
			" " \
			"$line" \
			" "
	done
}

redraw() {
	clear_screen
	title_line
	#DEBUG="$current_menu_name"
	#DEBUG="$current_menu_content"
	status_line
	printf "$TEXT_START"
	if [[ -n "$current_menu_content" ]]; then
		printf "$current_menu_content\n\n"
	fi
	if [[ -z "$1" ]]; then
		draw_menu
	fi
}

draw_menu() {
	if [[ -n "${current_menu[@]}" ]]; then
		local i=0
		if (( scroll_position+max_items < current_menu_length && active_item == max_items-1 )); then
			(( scroll_position++ ))
			(( active_item-- ))
		elif (( scroll_position > 0 && active_item == 0 )); then
			(( scroll_position--))
			(( active_item++))
		fi
		for item in "${current_menu[@]:scroll_position:max_items}"; do
			if [[ "$i" -eq "$active_item" ]]; then
				printf "${RED}>${DEFAULT} "
			fi
			printf "${item}\n"
			((i++))
		done
	fi
}
#################################################
#
#    File management
#
#################################################
read_dir() {
	local dirs
	local files

	# If '$FIRMWARE_MENU' has more than 2 entries, reset it to the 2 original entries
	[[ "${#FIRMWARE_MENU[@]}" -gt "2" ]]; FIRMWARE_MENU=("${FIRMWARE_MENU[@]:0:2}")

	# If '$PWD' is '/', unset it to avoid '//'
	[[ "$PWD" == "/" ]] && PWD=

	for item in "$PWD"/*; do
		if [[ -d "$item" ]]; then
			dirs+=($(basename "$item"))
		else
			ext="${item##*.}"
			if [[ "$ext" == "hex" || "$ext" == "bin" ]]; then
				files+=($(basename "$item"))
			fi
		fi
	done

	for dir in "${dirs[@]}"; do
		FIRMWARE_MENU+=("${BOLD_BLUE}${dir}/${DEFAULT}")
	done
	for file in "${files[@]}"; do
		FIRMWARE_MENU+=("${file}")
	done

	# Make sure we have up-to-date menu length before drawing
	current_menu_length="${#FIRMWARE_MENU[@]}"
}
#################################################
#
#    Doctor
#
#################################################
MAIN_MENU_doctor() {
	enter_menu "doctor"

	DOCTOR_MENU_CONTENT=""
	DOCTOR_MENU_CONTENT="${BORDER}Environment:${DEFAULT}\n"
	DOCTOR_MENU_CONTENT+="OS: $OS\n"
	DOCTOR_MENU_CONTENT+="Shell: $SHELL - $BASH_VERSION\n"
	DOCTOR_MENU_CONTENT+="Terminfo: $TERM\n"
	DOCTOR_MENU_CONTENT+="Window size: ${COLUMNS}x${LINES}\n"
	if [ "$OS" == "linux" ]; then
		DOCTOR_MENU_CONTENT+="Udev file: "
		QMK_UDEV_FILE="50-qmk.rules"
		if [ -s "/usr/lib/udev/rules.d/$QMK_UDEV_FILE" ]; then
			DOCTOR_MENU_CONTENT+="/usr/lib/udev/rules.d/$QMK_UDEV_FILE\n"
		elif [ -s "/usr/local/lib/udev/rules.d/$QMK_UDEV_FILE" ]; then
			DOCTOR_MENU_CONTENT+="/usr/local/lib/udev/rules.d/$QMK_UDEV_FILE\n"
		elif [ -s "/run/udev/rules.d/$QMK_UDEV_FILE" ]; then
			DOCTOR_MENU_CONTENT+="/run/udev/rules.d/$QMK_UDEV_FILE\n"
		elif [ -s "/etc/udev/rules.d/$QMK_UDEV_FILE" ]; then
			DOCTOR_MENU_CONTENT+="/etc/udev/rules.d/$QMK_UDEV_FILE\n"
		else
			DOCTOR_MENU_CONTENT+="${RED}Not available${DEFAULT}, flashing without root will likely fail.\n"
		fi
	fi

	DOCTOR_MENU_CONTENT+="\n${BORDER}Tools:${DEFAULT}\n"
	DOCTOR_MENU_CONTENT+="Dfu-util version: "
	if [[ -x "$DFU_UTIL" ]]; then
		DOCTOR_MENU_CONTENT+=$(check_dfu_util_version)
		DOCTOR_MENU_CONTENT+="\n"
	else
		DOCTOR_MENU_CONTENT+="${RED}Not available${DEFAULT}, flashing ARM-based boards might not be possible.\n"
	fi
	DOCTOR_MENU_CONTENT+="Avrdude version: "
	if [[ -x "$AVRDUDE" ]]; then
		DOCTOR_MENU_CONTENT+=$(check_avrdude_version)
		DOCTOR_MENU_CONTENT+="\n"
	else
		DOCTOR_MENU_CONTENT+="${RED}Not available${DEFAULT}, flashing ProMicro-based boards might not be possible.\n"
	fi
	DOCTOR_MENU_CONTENT+="Dfu-programmer version: "
	if [[ -x "$DFU_PROGRAMMER" ]]; then
		DOCTOR_MENU_CONTENT+=$(check_dfu_programmer_version)
		DOCTOR_MENU_CONTENT+="\n"
		#DOCTOR_MENU_CONTENT+=$("$DFU_PROGRAMMER" -V 2>&1 | awk '/^dfu-programmer/ {print $2}'\n)
	else
		DOCTOR_MENU_CONTENT+="${RED}Not available${DEFAULT}, flashing AVR-based boards might not be possible.\n"
	fi

	# redraw
}
#################################################
#
#    Flashing
#
#################################################
#
#    Flashing: OS-specific functions
#
#################################################
find_bootloader_linux() {
	# Based on https://serverfault.com/a/984649
	vendor=${1%:*}
	product=${1##*:}

	sys=/sys/bus/usb/devices

	# Iterate over the dirs in the sysfs
	for d in "$sys"/*; do
		path="$d"
		if [[ -f "${path}/idProduct" ]]; then
			prod=$(cat "${path}/idProduct")
			vend=$(cat "${path}/idVendor")

			# Until we find a device with a matching VID and PID
			if [[ "$vend" == "$vendor"  && "$prod" == "$product" ]]; then
				tty="${path}:1.0/tty"
				# Check if the "tty" subdir exists
				if [[ -d "$tty" ]]; then
					devname=($(compgen -G "${tty}/*"))
					# For Caterina, only a single dir should exist with the name of the device
					if [[ "${#devname[@]}" -eq "1" && -d ${devname[0]} ]]; then
						echo "/dev/$(basename ${devname[0]})"
						return
					fi
				fi
				# For non-Caterina devices, just return the sysfs path
				echo "$path"
				return
			fi
		fi
	done
}
#################################################
#
#    Flashing: Generic functions
#
#################################################
find_bootloader() {
	# To avoid running forever, only look for bootloaders for ~5mins
	local TIMEOUT=600
	local counter=0
	local find_bl=""

	if [ "$OS"  == "linux" ]; then
		find_bl="find_bootloader_linux"
	fi

	printf "Waiting for bootloader"
	while [[ -z "$bootloader" && "$counter" -lt "$TIMEOUT" ]] ; do
		printf "."
		for bl in "${!BOOTLOADERS[@]}"; do
			rc="$($find_bl $bl)"
			if [[ -n "$rc" ]]; then
				read -r bootloader mcu < <(echo "${BOOTLOADERS[$bl]}")
				if [[ "$bootloader" == "caterina" ]]; then
					# For Caterina devices, we save the tty device in the mcu variable
					# (mcu is always atmega32u4 anyway)
					mcu="$rc"
				fi
				# Exit if we've found the bootloader
				break
			fi
		done
		sleep 0.5
		(( counter++ ))
	done
	[[ -n "$bootloader" ]] && printf " Found it!\n\n" || (printf " Timed out!\n"; back)
}

flash_atmel_dfu() {
	if [[ -z "$DFU_PROGRAMMER" ]]; then
		printf "${RED}ERROR:${DEFAULT} The 'dfu-programmer' command is not available!\n"
		return
	fi
	IFS='.' read -r maj min bug < <(check_dfu_programmer_version)
	if [[ "$maj" -eq "0" && "$min" -lt "7" ]]; then
		# Ubuntu and Debian still ships 0.6.1
		force=""
	else
		# Only version 0.7.0 and higher supports '--force'
		force="--force"
	fi
	"$DFU_PROGRAMMER" "$mcu" erase "$force" 2>&1
	"$DFU_PROGRAMMER" "$mcu" flash "$force" "$firmware" 2>&1
	"$DFU_PROGRAMMER" "$mcu" reset 2>&1
}

flash_caterina() {
	if [[ -z "$AVRDUDE" ]]; then
		printf "${RED}ERROR:${DEFAULT} The 'avrdude' command is not available!\n"
		return
	fi
	local port="$mcu"
	if [[ -n "$port" ]]; then
		flash_arg="flash:w:${firmware}:i"
		$AVRDUDE -p atmega32u4 -c avr109 -U flash:w:"${firmware}":i -P $port 2>&1
	else
		printf "${RED}ERROR:${DEFAULT} Couldn't identify the device!\n"
	fi
}
#################################################
#
#    Flashing: Menu functions
#
#################################################
FLASH_MENU_firmware() {
	enter_menu "firmware"
	read_dir
}

FLASH_MENU_flash() {
	enter_menu "flashing"
	redraw "nomenu"
	find_bootloader
	if [[ "$bootloader" == "atmel-dfu" ]]; then
		flash_atmel_dfu
	elif [[ "$bootloader" == "caterina" ]]; then
		flash_caterina
	fi
	# if [[ -n "$bootloader" ]]; then
	# fi
	printf "\n\n${RED}>${DEFAULT} Back"
	read
	bootloader=""
	mcu=""
	back
}

MAIN_MENU_flash() {
	if [[ -n "$firmware" && "$FLASH_MENU[1]" != "Flash" ]]; then
		temp=("${FLASH_MENU[@]:1}")
		FLASH_MENU=("${FLASH_MENU[@]:0:1}")
		FLASH_MENU[1]="${RED}Flash${DEFAULT}\n"
		FLASH_MENU+=($temp)
	fi
	enter_menu "flash"
	# local file=""
	# redraw
}
#################################################
#
#    Special functions
#
#################################################
quit() {
	exit ${1:-0}
}

back() {
	exit_menu
	CONTENT=""
	scroll_position=0
}

menu_scrolling() {
	# If 'active_item' is negative, top->bottom looping will happen
	# and we need to scroll over to the end of the list
	if [[ "$active_item" -lt 0 && "$current_menu_length" -gt "$max_items" ]]; then
		scroll_position=$((current_menu_length - max_items))
	# If it's equal to 'max_items', bottom->top looping will happen
	# and we need to loop over to the beginning of the list
	elif [[ "$active_item" -eq "$max_items" && "$current_menu_length" -gt "$max_items" ]]; then
		scroll_position=0
	fi

	# Handle looping over in the menu
	local modulo
	[[ "$current_menu_length" -gt "$max_items" ]] && modulo="$max_items" || modulo="$current_menu_length"
	active_item=$(( ((active_item % modulo) + modulo) % modulo))
}

key() {
	# Handle special key presses.
	[[ $1 == $'\e' ]] && {
		read "${read_flags[@]}" -rsn 2

		# Handle a normal escape key press.
		[[ ${1}${REPLY} == $'\e\e['* ]] &&
			read "${read_flags[@]}" -rsn 1 _

		local special_key=${1}${REPLY}
	}

	#DEBUG="${1}:${REPLY}:${special_key}"
	#case ${special_key:-$1} in
	case "$REPLY" in
		# Go up
		"[A"|"0A"|"k")
			active_item=$((active_item - 1))
			menu_scrolling
			;;
		# Go down
		"[B"|"0B"|"j")
			active_item=$((active_item + 1))
			menu_scrolling
			;;
		# ENTER
		"")
			ptr=$(( scroll_position+active_item ))
			local selected_menu="$(clear_formatting ${current_menu[ptr]})"
			local selected_menu_lc="${selected_menu,,}"
			if [[ "$selected_menu_lc" == "back" || "$selected_menu_lc" == "quit" ]]; then
				# These are special, non menu-specific commands
				eval "${selected_menu_lc}"
			elif [[ "$current_menu_name" == "FIRMWARE_MENU" ]]; then
				# In the firmware selector menu
				#
				# if it's a dir, 'cd' into it
				if [[ -d "$selected_menu" ]]; then
					cd "$selected_menu"
					read_dir
					# return
				## if a file, select it for flashing
				elif [[ -f "$selected_menu" ]]; then
					firmware="${PWD}/$selected_menu"
					# For visual feedback,
					# make sure the menu entry only contains the first word,
					# and add the full path of the selected firmware
					FLASH_MENU[0]="${FLASH_MENU[0]%%' '*}"
					if [[ "${FLASH_MENU[0]: -2}" == "\n" ]]; then
						FLASH_MENU[0]="${FLASH_MENU[0]:0:-2}"
					fi
					FLASH_MENU[0]+=" : $firmware"
					back
				fi
			else
				eval "${current_menu_name}_${selected_menu_lc}"
			fi
			#redraw
			#${MAIN_MENU[active_item],,}
			#quit 1
			;;
		# Quit
		"q")
			# quit 0
			# echo "$(date +%Y-%m-%d/%H:%M:%S) - $current_menu_name" >> qmk.log
			[[ "$current_menu_name" != "MAIN_MENU" ]] && exit_menu
			;;
	esac
	# active_menu_length=$((current_menu_length + 1))
	# active_item=$(( ((active_item % active_menuo_length) + active_menu_length) % active_menu_length))
	#echo "scroll_position: $scroll_position" &>2
	#echo "active_item: $active_item" &>2
	#echo "current_menu_length-max_items: $(( max_items ))" &>2
	#if $(( scroll_position == 0 && active_item >= max_items )); then
	#	scroll_position=$(( current_menu_length - max_items ))
	#elif $(( active_item ==
	#fi
	redraw
}
#################################################

#get_term_size
#clear_screen
#setup_terminal
#status_line

#reset_terminal
# clear screen
#printf '\e[2J\e[H'

# Move the cursor to last line.
#printf "\e[${LINES}H"
#echo "hello"

#printf "\e[H"
#echo "world"
main() {
	# Reset the terminal on the exit signal (e.g.: Ctrl-C)
	trap 'reset_terminal' EXIT

	# Handle window resizing
	trap 'get_term_size; redraw' WINCH

	get_term_size
	setup_terminal
	redraw
	#title_line
	#status_line
	#menu

	while true; do
		# menu
		#sleep 0.1
		read "${read_flags[@]}" -srn 1 && key "$REPLY"

		# Exit if there is no longer a terminal attached.
		[[ -t 1 ]] || exit 1
	done
	#menu
	# tree /home/peti/Documents
	# tree
	reset_terminal

}

main "$@"
