# ======================================================================
# 基本設定
# ======================================================================

# 競合避けるためmask
sudo systemctl stop wpa_supplicant.service
sudo systemctl mask wpa_supplicant.service

sudo systemctl stop hostapd-network.service
sudo systemctl mask hostapd-network.service

# WifiデバイスをNetworkManagerの管理下から除外
sudo tee /etc/NetworkManager/conf.d/unmanaged.conf >/dev/null <<'EOF'
[keyfile]
unmanaged-devices=sinterface-name:wlo*;interface-name:wlx*;interface-name:p2p-*
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
device_name=GroundStation
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

# グループを新規作成し、仮想アクセスポイントを起動
sudo wpa_cli -i wlo1 p2p_group_add freq=2437

# ======================================================================

# <Client join>
# ClientからのPBC要求を待つ

# ======================================================================

# PBC(WPS Push Button Configuration)要求の受理
sudo wpa_cli -p /var/run/wpa_supplicant -i p2p-wlo1-0 wps_pbc

# ======================================================================

# IPv4アドレスを割り当て
sudo ip addr add 192.168.49.1/24 dev p2p-wlo1-0

# ======================================================================

# サービスログ確認
sudo journalctl -u wpa_supplicant@wlo1 -f

# ======================================================================

# 接続確立後のステータス確認
iw dev $(basename /sys/class/net/p2p-wlo1-*) info 2>/dev/null
sudo wpa_cli -i "$(basename /sys/class/net/p2p-wlo1-*)" status 2>/dev/null
ip addr show $(ls /sys/class/net/ | grep ^p2p-wlo1-)

iw dev $(basename /sys/class/net/p2p-wlo1-*) station dump
sudo wpa_cli -i wlo1 p2p_peer da:3a:dd:09:24:2a

# ======================================================================
# AP mode
# ======================================================================

# 1. hostapd.service (AP起動)
sudo systemctl unmask hostapd.service 2>/dev/null || true

sudo tee /etc/hostapd/hostapd.conf >/dev/null <<'EOF'
interface=wlxe0e1a91d6625
driver=nl80211
ssid=AP-GroundStation
hw_mode=g
channel=6
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=wlxe0e1a91d6625
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

# hostapd設定の参照パスを更新
sudo sed -i 's/^#DAEMON_CONF=.*/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/' /etc/default/hostapd

# IPの割り当てとhostapdがdnsmasqより先に起動するように設定
sudo systemctl edit hostapd
```
[Service]
ExecStartPost=/bin/sleep 2
ExecStartPost=/usr/sbin/ip addr add 192.168.50.1/24 dev wlxe0e1a91d6625

[Unit]
Before=dnsmasq.service
```

# 2. dnsmasq.service (DHCP起動)
sudo systemctl unmask dnsmasq.service 2>/dev/null || true

# port=0 DNSは提供しない（systemd-resolvedに任せる）
sudo tee /etc/dnsmasq.conf >/dev/null <<'EOF'
interface=wlxe0e1a91d6625
bind-interfaces
dhcp-range=192.168.50.10,192.168.50.50,255.255.255.0,24h
port=0
EOF

# 更新して有効化
sudo systemctl daemon-reload

sudo systemctl enable hostapd
sudo systemctl enable dnsmasq

# 再起動して確認
sudo systemctl restart hostapd
sudo systemctl restart dnsmasq

sudo systemctl status hostapd
sudo systemctl status dnsmasq

ip addr show wlxe0e1a91d6625
iw dev wlxe0e1a91d6625 info

# ログ
sudo journalctl -u hostapd-network -f
sudo journalctl -u hostapd -f
sudo journalctl -u dnsmasq -f
sudo journalctl -xeu dnsmasq.service
