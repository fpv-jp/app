#!/bin/bash
# p2p-config-tui.sh - raspi-config-style Wi-Fi Direct (P2P) setup menu
# Requires: whiptail, wpa_cli, ip, iw, systemd (journalctl), bash
# Optional: NetworkManager, wpa_supplicant@<iface>.service
# License: MIT

set -euo pipefail

TITLE="P2P Config Tool"
IFACE_DEFAULT="wlan0"
FREQ_DEFAULT="2437"   # ch6
IP_DEFAULT_GO="192.168.49.1/24"
IP_DEFAULT_CL="192.168.49.2/24"

# --- helpers ---
require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 127; }; }
msg() { whiptail --title "$TITLE" --msgbox "$1" 15 70; }
yesno() { whiptail --title "$TITLE" --yesno "$1" 12 70; }
input() { 
  local prompt="$1" default="${2:-}"
  whiptail --title "$TITLE" --inputbox "$prompt" 10 70 "$default" 3>&1 1>&2 2>&3
}
textbox() {
  local text="$1"
  whiptail --title "$TITLE" --scrolltext --msgbox "$text" 25 90
}
run() {
  local cmd="$1"
  local out rc
  if out=$(bash -lc "$cmd" 2>&1); then
    textbox "$ $cmd

$out"
  else
    rc=$?
    textbox "$ $cmd

$out

[rc=$rc]"
  fi
}

write_file_sudo() {
  local target="$1" content="$2" tmp
  tmp=$(mktemp)
  printf '%s\n' "$content" >"$tmp"
  sudo mkdir -p "$(dirname "$target")"
  if sudo install -m 0644 "$tmp" "$target"; then
    rm -f "$tmp"
    textbox "Updated ${target}

${content}"
  else
    rm -f "$tmp"
    msg "Failed to write ${target}"
    return 1
  fi
}

detect_iface() {
  # pick first wlan*/wlo* that exists
  for n in /sys/class/net/*; do
    b=$(basename "$n")
    [[ "$b" =~ ^wlan[0-9]+$ || "$b" =~ ^wlo[0-9]+$ ]] && { echo "$b"; return; }
  done
  echo "$IFACE_DEFAULT"
}

p2p_name() {
  local base="$1"
  # first p2p-<iface>-* that exists
  shopt -s nullglob
  for n in /sys/class/net/p2p-"$base"-*; do
    [[ -e "$n" ]] && { basename "$n"; return; }
  done
  echo ""
}

show_systemd_status() {
  local iface="$1"
  run "systemctl status -n 0 wpa_supplicant@${iface}"
}

show_iw_status() {
  run "iw dev"
}

show_wpa_status() {
  local iface="$1"
  local p2p="$(p2p_name "$iface")"
  run "wpa_cli -i ${iface} status"
  if [ -n "$p2p" ]; then
    run "wpa_cli -i ${p2p} status"
  else
    msg "No P2P interface yet (run GO start first)."
  fi
}

tail_logs() {
  local iface="$1"
  run "journalctl -u wpa_supplicant@${iface} -n 200 --no-pager"
}

setup_environment() {
  local setup_iface setup_cfg setup_device setup_nm force_client cfg_path nm_content config_content override_dir override_path override_content
  setup_iface=$(input "Wi-Fi interface to configure (e.g., wlan0 / wlo1)" "$iface") || true
  setup_iface=${setup_iface:-$iface}
  [ -z "${setup_iface:-}" ] && { msg "Interface is required for setup."; return; }

  local default_cfg="wpa_supplicant-${setup_iface}.conf"
  setup_cfg=$(input "wpa_supplicant config filename (stored under /etc/wpa_supplicant)" "$default_cfg") || true
  setup_cfg=${setup_cfg:-$default_cfg}

  setup_device=$(input "Device name advertised over P2P" "P2PDevice") || true
  setup_device=${setup_device:-P2PDevice}

  local default_nm="interface-name:${setup_iface};interface-name:p2p-*"
  setup_nm=$(input "NetworkManager unmanaged-devices entry" "$default_nm") || true
  setup_nm=${setup_nm:-$default_nm}

  force_client=0
  if yesno "Force client intent (add p2p_go_intent=0)?"; then
    force_client=1
  fi

  config_content="ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1"
  if [ "$force_client" -eq 1 ]; then
    config_content+=$'\n'"p2p_go_intent=0"
  fi
  config_content+=$'\n'"device_name=${setup_device}"
  config_content+=$'\n'"device_type=1-0050F204-1"
  config_content+=$'\n'"config_methods=virtual_push_button physical_display keypad"

  cfg_path="/etc/wpa_supplicant/${setup_cfg}"
  nm_content="[keyfile]
unmanaged-devices=${setup_nm}"
  override_dir="/etc/systemd/system/wpa_supplicant@${setup_iface}.service.d"
  override_path="${override_dir}/override.conf"
  override_content="[Service]
ExecStart=
ExecStart=/usr/sbin/wpa_supplicant -Dnl80211 -i${setup_iface} -c${cfg_path}
"

  run "sudo systemctl stop wpa_supplicant.service || true"
  run "sudo systemctl mask wpa_supplicant.service"
  write_file_sudo "/etc/NetworkManager/conf.d/unmanaged.conf" "$nm_content" || return
  write_file_sudo "$cfg_path" "$config_content" || return
  write_file_sudo "$override_path" "$override_content" || return
  run "sudo systemctl daemon-reload"
  run "sudo systemctl enable --now wpa_supplicant@${setup_iface}.service"
  run "sudo systemctl restart NetworkManager"
  msg "Setup completed for ${setup_iface}. Config: ${cfg_path}"
  iface="$setup_iface"
}

# --- main menu loop ---
main_menu() {
  local iface freq ip_go ip_cl
  iface="$(detect_iface)"
  freq="$FREQ_DEFAULT"
  ip_go="$IP_DEFAULT_GO"
  ip_cl="$IP_DEFAULT_CL"

  while true; do
    CHOICE=$(whiptail --title "$TITLE" --menu "IFACE=${iface} | FREQ=${freq}\nChoose an action:" 22 78 14 \
      "0" "Run setup (mask/NetworkManager/wpa_supplicant)" \
      "1" "Start GO (p2p_group_add freq=…)" \
      "2" "Accept WPS (GO: wps_pbc)" \
      "3" "Start discovery (p2p_find) / list peers (p2p_peers)" \
      "4" "Connect as client (p2p_connect <MAC> pbc join)" \
      "5" "Assign IP (GO/Client)" \
      "6" "Show systemctl status" \
      "7" "Show iw dev" \
      "8" "Show wpa_cli status" \
      "9" "Show logs (journalctl -u wpa_supplicant@IFACE)" \
      "10" "Change settings (IFACE / FREQ / IP)" \
      "11" "Exit" 3>&1 1>&2 2>&3) || exit 0

    case "$CHOICE" in
      0)  setup_environment ;;
      1)  # GO start
          freq=$(input "Enter frequency in MHz (e.g., 2437=Ch6)" "$freq") || true
          run "sudo wpa_cli -i ${iface} p2p_group_add freq=${freq}"
          local p2p="$(p2p_name "$iface")"
          run "iw dev ${p2p:-p2p-${iface}-0} info || true"
          ;;
      2)  # WPS accept
          local p2p="$(p2p_name "$iface")"
          if [ -z "$p2p" ]; then msg "No P2P interface found. Start GO first."; continue; fi
          run "sudo wpa_cli -i ${p2p} wps_pbc"
          ;;
      3)  # find & peers
          run "sudo wpa_cli -i ${iface} p2p_find"
          run "sudo wpa_cli -i ${iface} p2p_peers"
          ;;
      4)  # connect as client
          MAC=$(input "Target MAC address (e.g., bc:09:1b:1d:15:92)" "") || true
          [ -z "${MAC:-}" ] && { msg "MAC address was not provided."; continue; }
          run "sudo wpa_cli -i ${iface} p2p_connect ${MAC} pbc join"
          ;;
      5)  # assign IP
          local p2p="$(p2p_name "$iface")"
          if [ -z "$p2p" ]; then msg "No P2P interface found."; continue; fi
          if yesno "Assign ${ip_go} to the GO? Selecting No assigns the client (${ip_cl})."; then
            ip=$(input "Enter IP/CIDR to assign" "$ip_go") || true
          else
            ip=$(input "Enter IP/CIDR to assign" "$ip_cl") || true
          fi
          [ -z "${ip:-}" ] && { msg "IP/CIDR was not provided."; continue; }
          run "sudo ip addr add ${ip} dev ${p2p}"
          run "ip addr show ${p2p}"
          ;;
      6)  show_systemd_status "$iface" ;;
      7)  show_iw_status ;;
      8)  show_wpa_status "$iface" ;;
      9)  tail_logs "$iface" ;;
      10) # settings
          iface=$(input "Enter Wi-Fi interface (e.g., wlan0 / wlo1)" "$iface") || true
          freq=$(input "Default frequency (MHz)" "$freq") || true
          ip_go=$(input "Default GO IP/CIDR" "$ip_go") || true
          ip_cl=$(input "Default client IP/CIDR" "$ip_cl") || true
          ;;
      11) clear; exit 0 ;;
    esac
  done
}

# requirements check
require whiptail
require wpa_cli
require iw
require ip
# journalctl may not exist on tiny systems; menu will still work without it
command -v journalctl >/dev/null 2>&1 || true

main_menu
