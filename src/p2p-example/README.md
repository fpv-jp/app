iw dev

iw phy phy2 info

iw list | grep -A3 Frequencies

sudo iw dev wlan2 scan

特定のSSIだけ表示することってできますか？

sudo iw dev wlan2 scan ssid "AP-GroundStation"

受信強度 (dBm)	品質	状況のイメージ
-30 ~ -50	最高	数メートル内。壁ほぼなし。非常に安定。
-50 ~ -60	良好	通常運用で問題なし。速度も出る。
-60 ~ -70	普通	途切れる可能性あり。速度落ちる。
-70 ~ -80	弱い	動画や高負荷通信は不安定。P2P は切れやすい。
-80 以下	ほぼ不可	接続が途切れやすい。性能発揮できない。

Wi-Fiチップ/ドライバが Wi-Fi Direct(P2P)をサポートしている必要があります
```bash
iw list | grep -A10 "Supported interface modes"

	Supported interface modes:
		 * P2P-client
		 * P2P-GO
		 * P2P-device
```
Mac は Wi-Fi Direct(P2P) に対応していません


Wi-Fiチップ/ドライバが Accecc Point(AP)をサポートしている必要があります
```bash
iw list | grep -A10 "Supported interface modes"

	Supported interface modes:
		 * AP
```
Mac は Accecc Point(AP) に対応していません



BSS e0:e1:a9:1d:66:25(on wlan2)
	TSF: 18375168038 usec (0d, 05:06:15)
	freq: 5660.0
	beacon interval: 100 TUs
	capability: ESS Privacy ShortSlotTime (0x0411)
	signal: -49.00 dBm
	last seen: 1224 ms ago
	SSID: AP-GroundStation
	Supported rates: 1.0* 2.0* 5.5* 11.0* 6.0 9.0 12.0 18.0
	DS Parameter set: channel 6
	TIM: DTIM Count 0 DTIM Period 2 Bitmap Control 0x0 Bitmap[0] 0x0
	ERP: Barker_Preamble_Mode
	Extended supported rates: 24.0 36.0 48.0 54.0
	RSN:	 * Version: 1
		 * Group cipher: CCMP
		 * Pairwise ciphers: CCMP
		 * Authentication suites: PSK
		 * Capabilities: 1-PTKSA-RC 1-GTKSA-RC (0x0000)
	Extended capabilities:
		 * Extended Channel Switching
		 * SSID List
		 * Operating Mode Notification
		 
raspi@raspi-4b:~ $ wpa_cli -i wlan2 signal_poll
RSSI=-21
LINKSPEED=54
NOISE=9999
FREQUENCY=2437
WIDTH=20 MHz (no HT)
CENTER_FRQ1=2437
AVG_RSSI=-21
AVG_BEACON_RSSI=-21

raspi@raspi-4b:~ $ wpa_cli -i wlan2 scan_results
bssid / frequency / signal level / flags / ssid
e0:e1:a9:1d:66:25	2437	-45	[WPA2-PSK-CCMP][ESS]	AP-GroundStation
raspi@raspi-4b:~ $




wpa_cli signal_poll