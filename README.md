# app
VRX UI app, signaling server, and certificate container

1. Start the signaling server and vrx UI
```bash
docker run -it -d \
  --user root \
  --name fpvjp-app \
  -p 443:443 \
  --restart unless-stopped \
  fpvjp/app:latest
```

2. Copy the CA certificate
```bash
docker cp fpvjp-app:/app/certificate/server-ca-cert.pem /opt/vtx/
```

# dev
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

cargo build --release

cp target/debug/fpvjp-app .

sudo ./fpvjp-app --port 443 --cert certificate/server-cert.pem --key certificate/server-key.pem --debug --keep-alive
```
