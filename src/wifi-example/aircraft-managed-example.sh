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
# managed mode
# ======================================================================

# 1. wpa_supplicant設定
sudo tee /etc/wpa_supplicant/wpa_supplicant-wlan1.conf >/dev/null <<'EOF'
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
EOF
# SSID/Passを追記する
wpa_passphrase "AP-GroundStation" "AP-GroundStation" | sudo tee -a /etc/wpa_supplicant/wpa_supplicant-wlan1.conf

# 1-2. パスワードを使わない wpa_supplicant設定
sudo tee /etc/wpa_supplicant/wpa_supplicant-wlan1.conf >/dev/null <<'EOF'
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
network={
    ssid="AP-GroundStation"
    key_mgmt=NONE
}
EOF

# サービスを作成
sudo systemctl enable wpa_supplicant@wlan1
# サービス起動時にIPを追加するようにoverride
sudo systemctl edit wpa_supplicant@wlan1
```
[Service]
ExecStartPost=/bin/sleep 2
ExecStartPost=/usr/sbin/ip addr replace 192.168.50.2/24 dev wlan1
```
# サービスを確認
sudo systemctl cat wpa_supplicant@wlan1

# ======================================================================

# サービスを更新して再起動
sudo systemctl daemon-reload
sudo systemctl restart wpa_supplicant@wlan1

# 疎通確認
ping 192.168.50.1

# ======================================================================

sudo systemctl status wpa_supplicant@wlan1

sudo journalctl -u wpa_supplicant@wlan1 -f

ip addr show wlan1
wpa_cli -i wlan1 status
wpa_cli -i wlan1 signal_poll
