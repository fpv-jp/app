wget https://raw.githubusercontent.com/fpv-jp/app/refs/heads/main/certificate/server-ca-cert.pem
sudo cp server-ca-cert.pem /usr/local/share/ca-certificates/my-custom-ca.crt
sudo update-ca-certificates

sudo apt update && sudo apt install xfce4
sudo apt purge '^kde' '^plasma' '^khotkeys' '^kwayland' '^kwin' '^kio' '^kmail' '^akonadi' '^libkf' '^kded' '^kdepim' -y
sudo apt autoremove --purge -y

sudo apt install xfce4 xfce4-goodies xrdp -y
sudo systemctl enable xrdp

echo "startxfce4" > ~/.xinitrc
chmod +x ~/.xinitrc

echo "exec startxfce4" > ~/.xsession
chmod +x ~/.xsession

sudo vim /etc/xrdp/startwm.sh
sudo usermod -aG adm rock
ls -l ~/.Xauthority ~/.ICEauthority

sudo systemctl restart xrdp

cat ~/.xorgxrdp.*.log
cat ~/.xsession-errors
journalctl -u xrdp -n 50
