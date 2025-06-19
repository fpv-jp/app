```
iw dev
iw phy phy1 info
sudo iw dev wlan2 scan
```

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
