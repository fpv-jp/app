# ======================================================================
# 基本設定
# ======================================================================

# wpa_supplicantは競合避けるためmask
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
# P2P-Client 接続
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

# サービスログ確認
sudo journalctl -u wpa_supplicant@wlan0 -f

# ======================================================================

# GO(group owner)を検索
sudo wpa_cli -i wlan0 p2p_find
sudo wpa_cli -i wlan0 p2p_peers
# 検出されたGOのMACアドレスに対してPBCを要求
sudo wpa_cli -i wlan0 p2p_connect bc:09:1b:1d:15:92 pbc join

# ======================================================================

# <GO wps_pbc>
# GO側でPBC要求の受け入れ

# ======================================================================

# PBCを受け入れて、接続できたらIPv4アドレスを割り当て
sudo ip addr add 192.168.49.2/24 dev p2p-wlan0-0

# 疎通確認
ping 192.168.49.1

# ======================================================================

# 接続確立後のステータス確認
iw dev $(basename /sys/class/net/p2p-wlan0-*) info 2>/dev/null
sudo wpa_cli -i "$(basename /sys/class/net/p2p-wlan0-*)" status 2>/dev/null
ip addr show $(ls /sys/class/net/ | grep ^p2p-wlan0-)

iw dev $(basename /sys/class/net/p2p-wlan0-*) station dump
sudo wpa_cli -i wlan0 p2p_peer bc:09:1b:1d:15:92s

ls -la /var/run/wpa_supplicant/
srwxrwx---  1 root netdev p2p-dev-wlan0
srwxrwx---  1 root netdev p2p-wlan0-0
srwxrwx---  1 root netdev wlan0
