#!/usr/bin/env bash
VERSION="0.0.1"
MAINTAINER="Erovia"

OS="$(uname -s)"
#################################################
#
#    TOOLS
#
#################################################
DFU_UTIL=$(command -v dfu-util 2>&1)
DFU_PROGRAMMER=$(command -v dfu-programmer 2>&1)
AVRDUDE=$(command -v avrdudex 2>&1)
#################################################
#
#    COLOURS
#
#################################################
DEFAULT="\e[0m"
RED="\e[31m"
BORDER="\e[30;41m"
#################################################
#
#    POSITIONS
#
#################################################
FIRST_LINE="\e[H"
#LAST_LINE="\e
TEXT_START="\e[3H"
#################################################
#
#    MENUS
#
#################################################
declare -a MAIN_MENU
MAIN_MENU[0]="Flash"
MAIN_MENU[1]="Doctor"
MAIN_MENU[2]="Quit"
declare -a FLASH_MENU
FLASH_MENU[0]="Flash"
FLASH_MENU[1]="Back"
declare -a DOCTOR_MENU
DOCTOR_MENU[0]="Back"
# DOCTOR_MENU[0]="Flash"
# DOCTOR_MENU[1]="Multi-Flash"

peek() { local -n "stack=$1"; printf %s\\n "${stack[-1]}"; }
menu_housekeeping() {
	active_item=0
	current_menu_name="$(echo $(peek 'menu_stack')_MENU | tr '[:lower:]' '[:upper:]')"
	declare -ng "current_menu=$current_menu_name"
	current_menu_length="${#current_menu[@]}"
	# echo "$(date +%Y-%m-%d/%H:%M:%S) - $current_menu_name: ${current_menu[@]}: ${#current_menu[@]}" >> qmk.log
}
push() { local -n "stack=$1"; shift; stack+=("$@"); menu_housekeeping; }
pop() { peek "$1"; unset "$1[-1]"; menu_housekeeping; }
push "menu_stack" "main"
# push "menu_stack" "flash"
# pop "menu_stack"

MENU_POSITION=""
#################################################
CONTENT=""


DEBUG=""

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

	((max_items=LINES-1))
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
	if [[ -z "$CONTENT" ]]; then
		clear_screen
	fi
	title_line
	DEBUG="$current_menu_name"
	status_line
	printf "$TEXT_START"
	if [[ -n "$CONTENT" ]]; then
		printf "$CONTENT\n\n"
	fi
	#read
	draw_menu
	# if [[ "$(peek 'menu_stack')" == "main" ]]; then
		# main_menu
		# draw_menu
	# fi
}

draw_menu() {
	echo "$(date +%Y-%m-%d/%H:%M:%S) - draw_menu - $active_item" >> qmk.log
	echo "$(date +%Y-%m-%d/%H:%M:%S) - draw_menu - $current_menu_name: ${current_menu[@]}: ${#current_menu[@]}" >> qmk.log
	if [[ -n "${current_menu[@]}" ]]; then
		for ((i = 0; i < $current_menu_length; i++)); do
			if [[ "$i" -eq "$active_item" ]]; then
				printf "${RED}>${DEFAULT} "
			fi
			printf "${current_menu[$i]}\n"
		done
	fi
}


quit() {
	exit ${1:-0}
}

back() {
	CONTENT=""
	pop "menu_stack"
}


doctor() {
	push "menu_stack" "doctor"

	CONTENT="${BORDER}Environment:${DEFAULT}\n"
	CONTENT+="OS: $OS\n"
	CONTENT+="Shell: $SHELL - $BASH_VERSION\n"
	if [ $(echo $OS | tr '[:upper:]' '[:lower:]')  == "linux" ]; then
		CONTENT+="Udev file: "
		QMK_UDEV_FILE="50-qmk.rules"
		if [ -s "/usr/lib/udev/rules.d/$QMK_UDEV_FILE" ]; then
			CONTENT+="/usr/lib/udev/rules.d/$QMK_UDEV_FILE"
		elif [ -s "/usr/local/lib/udev/rules.d/$QMK_UDEV_FILE" ]; then
			CONTENT+="/usr/local/lib/udev/rules.d/$QMK_UDEV_FILE"
		elif [ -s "/run/udev/rules.d/$QMK_UDEV_FILE" ]; then
			CONTENT+="/run/udev/rules.d/$QMK_UDEV_FILE"
		elif [ -s "/etc/udev/rules.d/$QMK_UDEV_FILE" ]; then
			CONTENT+="/etc/udev/rules.d/$QMK_UDEV_FILE"
		else
			CONTENT+="${RED}Not available${DEFAULT}, flashing without root will likely fail.\n"
		fi
	fi

	CONTENT+="\n${BORDER}Tools:${DEFAULT}\n"
	CONTENT+="Dfu-util version: "
	if [[ -x "$DFU_UTIL" ]]; then
		CONTENT+=$("$DFU_UTIL" -V | awk '/^dfu-util/ {print $2}')
	else
		CONTENT+="${RED}Not available${DEFAULT}, flashing ARM-based boards might not be possible.\n"
	fi
	CONTENT+="Avrdude version: "
	if [[ -x "$AVRDUDE" ]]; then
		CONTENT+=$("$AVRDUDE" 2>&1 | awk '/^avrdude version/ {print $3}' | tr -d ',')
	else
		CONTENT+="${RED}Not available${DEFAULT}, flashing ProMicro-based boards might not be possible.\n"
	fi
	CONTENT+="Dfu-programmer version: "
	if [[ -x "$DFU_PROGRAMMER" ]]; then
		CONTENT+=$("$DFU_PROGRAMMER" -V 2>&1 | awk '/^dfu-programmer/ {print $2}')
	else
		CONTENT+="${RED}Not available${DEFAULT}, flashing AVR-based boards might not be possible.\n"
	fi

	redraw
}


flash() {
	push "menu_stack" "flash"
	redraw
	# local file=""
	# local multiflash="false"
	# local active_item=0

	echo
	echo "Flashing stuff will come here."
	# for ((i = 0; i < $FLASH_MENU_LENGTH; i++)); do
	# 	if [[ "$i" -eq "$active_item" ]]; then
	# 		printf "${RED}>${DEFAULT} "
	# 	fi
	# 	printf "%s\n" "${FLASH_MENU[$i]}"
	# done
	# read
	# pop "menu_stack"
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
			;;
		# Go down
		"[B"|"0B"|"j")
			active_item=$((active_item + 1))
			;;
		# ENTER
		"")
			local selected_menu="$(echo ${current_menu[active_item]} | tr '[:upper:]' '[:lower:]')"
			#redraw
			eval "$selected_menu"
			#${MAIN_MENU[active_item],,}
			#quit 1
			;;
		# Quit
		"q")
			# quit 0
			# echo "$(date +%Y-%m-%d/%H:%M:%S) - $current_menu_name" >> qmk.log
			[[ "$current_menu_name" != "MAIN_MENU" ]] && pop "menu_stack"
			;;
	esac
	# active_menu_length=$((current_menu_length + 1))
	# active_item=$(( ((active_item % active_menu_length) + active_menu_length) % active_menu_length))
	active_item=$(( ((active_item % current_menu_length) + current_menu_length) % current_menu_length))
	redraw 
}

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
