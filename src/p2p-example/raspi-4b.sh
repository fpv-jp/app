# ======================================================================
# Client (Aircraft)
# ======================================================================

# wpa_supplicantは競合避けるため使用しません
sudo systemctl stop wpa_supplicant.service
sudo systemctl mask wpa_supplicant.service

# WifiデバイスをNetworkManagerの管理下から除外します
echo "[keyfile]
unmanaged-devices=interface-name:wlan*;interface-name:p2p-*" | sudo tee /etc/NetworkManager/conf.d/unmanaged.conf

sudo systemctl restart NetworkManager

# ドローン用のwpa_supplicant設定を作成
echo 'ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
p2p_go_intent=0
device_name=Aircraft
device_type=1-0050F204-1
config_methods=virtual_push_button physical_display keypad' | sudo tee /etc/wpa_supplicant/wpa_supplicant-aircraft.conf

# 使用するWifiデバイスのwpa_supplicantサービスを追加
sudo systemctl enable wpa_supplicant@wlan0.service
# ドローン用のwpa_supplicant設定を読み込むようにoverride
sudo systemctl edit wpa_supplicant@wlan0.service
```
[Service]
ExecStart=
ExecStart=/usr/sbin/wpa_supplicant -Dnl80211 -iwlan0 -c/etc/wpa_supplicant/wpa_supplicant-aircraft.conf
```
# 使用するWifiデバイスのwpa_supplicantサービスを起動
sudo systemctl daemon-reload
sudo systemctl enable --now wpa_supplicant@wlan0.service

# ======================================================================

# 関連サービスの状態を確認
sudo systemctl status NetworkManager
sudo systemctl status wpa_supplicant.service
sudo systemctl status wpa_supplicant@wlan0.service

# ======================================================================

# 既存の設定を初期化
sudo wpa_cli -i wlan0 p2p_cancel
sudo wpa_cli -i wlan0 p2p_stop_find
sudo wpa_cli -i wlan0 p2p_flush
sudo pkill -f wpa_supplicant
sudo ip link set wlan0 down
sudo ip link set wlan0 up
sudo systemctl restart wpa_supplicant@wlan0

# ======================================================================

# GO(group owner)に接続開始
sudo wpa_cli -i wlan0 p2p_find
sudo wpa_cli -i wlan0 p2p_peers
# 検出されたGOのMACアドレスに対してPBCを要求する
sudo wpa_cli -i wlan0 p2p_connect bc:09:1b:1d:15:92 pbc join

# ======================================================================

# <GO wps_pbc>
# GO側でPBC要求の受け入れ待ち

# ======================================================================

# サービスログ確認
sudo journalctl -u wpa_supplicant@wlan0 -f

# ======================================================================

# IPv4アドレスを割り当て
sudo ip addr add 192.168.49.2/24 dev p2p-wlan0-0

# ======================================================================

# 接続確立後のステータス確認
iw dev $(basename /sys/class/net/p2p-wlan0-*) info 2>/dev/null
sudo wpa_cli -i "$(basename /sys/class/net/p2p-wlan0-*)" status 2>/dev/null
ip addr show $(ls /sys/class/net/ | grep ^p2p-wlan0-)

iw dev $(basename /sys/class/net/p2p-wlan0-*) station dump
sudo wpa_cli -i wlan0 p2p_peer bc:09:1b:1d:15:92
