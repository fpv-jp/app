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
