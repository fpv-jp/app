# ======================================================================
# 基本設定
# ======================================================================

# 競合避けるためmask
sudo systemctl stop wpa_supplicant.service
sudo systemctl mask wpa_supplicant.service

# WifiデバイスをNetworkManagerの管理下から除外
sudo tee /etc/NetworkManager/conf.d/unmanaged.conf >/dev/null <<'EOF'
[keyfile]
unmanaged-devices=interface-name:wl*;interface-name:p2p-*
EOF

# NetworkManagerを再起動しwifiが管理されていない事を確認
sudo systemctl restart NetworkManager
nmcli device status

# ======================================================================
# P2P-GO mode
# ======================================================================

# 地上局用のwpa_supplicant設定を作成
echo "ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
device_name=GO-GroundStation
device_type=6-0050F204-1
p2p_ssid_postfix=_FPV
config_methods=virtual_push_button physical_display keypad" | sudo tee /etc/wpa_supplicant/wpa_supplicant-ground.conf

# 使用するWifiデバイスのwpa_supplicantサービスを追加
sudo systemctl enable wpa_supplicant@wlo1.service
# 地上局用のwpa_supplicant設定を読み込むようにoverride
sudo systemctl edit wpa_supplicant@wlo1.service
```
[Service]
ExecStart=
ExecStart=/usr/sbin/wpa_supplicant -Dnl80211 -iwlo1 -c/etc/wpa_supplicant/wpa_supplicant-ground.conf
```
# 使用するWifiデバイスのwpa_supplicantサービスを起動
sudo systemctl daemon-reload
sudo systemctl enable --now wpa_supplicant@wlo1.service

# ======================================================================

# 関連サービスの状態を確認
sudo systemctl status NetworkManager
sudo systemctl status wpa_supplicant.service
sudo systemctl status wpa_supplicant@wlo1.service

# ======================================================================

# 既存の設定を初期化
sudo wpa_cli -i wlo1 p2p_cancel
sudo wpa_cli -i wlo1 p2p_stop_find
sudo wpa_cli -i wlo1 p2p_flush
sudo pkill -f wpa_supplicant
sudo ip link set wlo1 down
sudo ip link set wlo1 up
sudo systemctl restart wpa_supplicant@wlo1

# ======================================================================

# サービスログ確認
sudo journalctl -u wpa_supplicant@wlo1 -f

# ======================================================================

# 仮想アクセスポイント(グループ)を起動
sudo wpa_cli -i wlo1 p2p_group_add freq=2437
# 例: channel 6 (2437 MHz)

# ======================================================================

# <Client join>
# ClientからのPBC要求を待ち

# ======================================================================

# PBC(WPS Push Button Configuration)要求を受理
sudo wpa_cli -p /var/run/wpa_supplicant -i p2p-wlo1-0 wps_pbc
# IPv4アドレスを割り当て
sudo ip addr add 192.168.49.1/24 dev p2p-wlo1-0

# ======================================================================

# <Client check>
# Clientで疎通確認

# ======================================================================

# 接続確立後のステータス確認
iw dev $(basename /sys/class/net/p2p-wlo1-*) info 2>/dev/null
sudo wpa_cli -i "$(basename /sys/class/net/p2p-wlo1-*)" status 2>/dev/null
ip addr show $(ls /sys/class/net/ | grep ^p2p-wlo1-)

iw dev $(basename /sys/class/net/p2p-wlo1-*) station dump
sudo wpa_cli -i wlo1 p2p_peer da:3a:dd:09:24:2a
