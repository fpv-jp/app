# app

Builds a container image for the signaling server bundled with VRX web resources.

This repository contains the signaling server source code and a self-signed CA for TLS.

```
# Signaling server
src/

# Self-signed CA certificates
certificate/
```

## 1. Certificates

For production deployments, it is recommended to regenerate the self-signed CA. These certificates enable TLS communication in air-gapped environments without access to the public internet.

```bash
cd certificate
bash gen-cert.sh
```

The server requires the following files for TLS termination:

```
certificate/server-cert.pem   # Server certificate
certificate/server-key.pem    # Server private key
```

Clients (browsers, API consumers, etc.) connecting to the server must trust the following CA certificate:

```
certificate/server-ca-cert.pem
```

## 2. Running the Server

The signaling server implements both a WebSocket endpoint for WebRTC SDP/ICE exchange and an HTTP server for hosting VRX web resources.

Start the container with:

```bash
docker run -it -d \
  --user root \
  --name fpvjp-app \
  -p 443:443 \
  --restart unless-stopped \
  fpvjp/app:latest
```

The signaling endpoint is available at:

```
wss://fpv/signaling
```

The VRX web application is served at the root path:

```
https://fpv/
```

For the VRX web application source code, see [vrx](https://github.com/fpv-jp/vrx).


## Development

To build and run the signaling server locally without Docker:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

cargo build --release

cp target/release/fpvjp-app .

sudo ./fpvjp-app --port 443 --cert certificate/server-cert.pem --key certificate/server-key.pem --debug --keep-alive
```
