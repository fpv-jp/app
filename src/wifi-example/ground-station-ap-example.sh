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
unmanaged-devices=interface-name:wl*;interface-name:p2p-*
EOF

# NetworkManagerを再起動しwifiが管理されていない事を確認
sudo systemctl restart NetworkManager
nmcli device status

# ======================================================================
# AP mode
# ======================================================================

# 1. hostapd.service (AP起動)
# ======================================================================

sudo apt install hostapd -y
sudo systemctl unmask hostapd.service

# 例: SSID AP-GroundStation / Password AP-GroundStation

sudo tee /etc/hostapd/hostapd.conf >/dev/null <<'EOF'
interface=wlP2p33s0
driver=nl80211
ssid=AP-GroundStation
hw_mode=g
channel=6
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=AP-GroundStation
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

# hostapd設定の参照パスを更新
sudo sed -i 's/^#DAEMON_CONF=.*/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/' /etc/default/hostapd

# IPの割り当てとhostapdがdnsmasqより先に起動するように設定
sudo systemctl edit hostapd.service
```
[Service]
ExecStartPost=/bin/sleep 2
ExecStartPost=/usr/sbin/ip addr replace 192.168.50.1/24 dev wlP2p33s0
Environment=DAEMON_OPTS=

[Unit]
Before=dnsmasq.service
```
# サービスを確認
sudo systemctl cat hostapd.service

# 2. dnsmasq.service (DHCP起動)
# ======================================================================

sudo apt install dnsmasq -y
sudo systemctl unmask dnsmasq.service 

# port=0 DNSは提供しない（systemd-resolvedに任せる）
sudo tee /etc/dnsmasq.conf >/dev/null <<'EOF'
interface=wlP2p33s0
bind-interfaces
dhcp-range=192.168.50.10,192.168.50.50,255.255.255.0,24h
port=0
EOF

# ======================================================================

# 更新して有効化
sudo systemctl daemon-reload
sudo systemctl enable hostapd.service dnsmasq.service

# 再起動して確認
sudo systemctl restart hostapd.service
sudo systemctl restart dnsmasq.service
sudo systemctl status hostapd.service 
sudo systemctl status dnsmasq.service

# ======================================================================

# ログ
sudo journalctl -u hostapd -f
sudo journalctl -u dnsmasq -f

sudo journalctl -xeu hostapd.service
sudo journalctl -xeu dnsmasq.service
