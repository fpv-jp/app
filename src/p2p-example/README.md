iw dev

iw phy phy2 info

iw list | grep -A3 Frequencies

sudo iw dev wlan2 scan


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
