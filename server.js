const TLS = process.env.TLS === 'true'
const DEBUG = process.env.DEBUG === 'true'
const KEEP_ALIVE = process.env.KEEP_ALIVE === 'true'

const INACTIVE_TIMEOUT = 60 * 60 * 1000 // 1 hour

console.log('TLS mode   :', TLS ? 'enabled' : 'disabled')
console.log('Debug log  :', DEBUG ? 'enabled' : 'disabled')
console.log('Keep alive :', KEEP_ALIVE ? 'enabled' : 'disabled')

// --------------------------------------------------
// signaling server for exchanging SDP/ICE in WebRTC
// --------------------------------------------------
import { WebSocketServer } from 'ws'
import { nanoid } from 'nanoid'

const MESSAGE_TYPE = {
  // Message types that the SENDER will listen for
  SENDER_SESSION_ID: 100,
  SENDER_RECEIVER_CLOSE: 108,
  SENDER_ERROR: 109,
  // Message types that the RECEIVER will listen for
  RECEIVER_SESSION_ID: 200,
  RECEIVER_SENDER_LIST: 201,
  RECEIVER_SENDER_CLOSE: 208,
  RECEIVER_ERROR: 209,
}

const CLIENT_TYPE = {
  SENDER: 'sender',
  RECEIVER: 'receiver',
}

// signalingHandler -----------------------------------
function signalingHandler(server) {
  const wsServer = new WebSocketServer({ server, path: '/signaling' })
  const wsMap = new Map()
  const pairMap = new Map()

  // ----------------------------------------------------------------------
  const getSenders = () =>
    Array.from(wsMap.values())
      .filter((client) => client.protocol === CLIENT_TYPE.SENDER)
      .map((client) => client.sessionId)

  // ----------------------------------------------------------------------
  const notifySenderList = () => {
    const senders = getSenders()

    for (const [ws, client] of wsMap) {
      if (client.protocol === CLIENT_TYPE.RECEIVER) {
        ws.send(JSON.stringify({ type: MESSAGE_TYPE.RECEIVER_SENDER_LIST, senders }))
      }
    }
  }

  // ----------------------------------------------------------------------
  const findClient = (protocol, sessionId) => {
    for (const [ws, client] of wsMap) {
      if (client.protocol === protocol && client.sessionId === sessionId) {
        return ws
      }
    }
    return null
  }

  // ----------------------------------------------------------------------
  const getTargetProtocol = (currentProtocol) => (currentProtocol === CLIENT_TYPE.RECEIVER ? CLIENT_TYPE.SENDER : CLIENT_TYPE.RECEIVER)

  // ----------------------------------------------------------------------
  const getTargetSessionId = (data, currentProtocol) => (currentProtocol === CLIENT_TYPE.RECEIVER ? data.ws1Id : data.ws2Id)

  // ----------------------------------------------------------------------
  const sendError = (ws, protocol, message) => {
    const errorType = protocol === CLIENT_TYPE.SENDER ? MESSAGE_TYPE.SENDER_ERROR : MESSAGE_TYPE.RECEIVER_ERROR
    ws.send(JSON.stringify({ type: errorType, message }))
  }

  wsServer.on('connection', (wsClient, request) => {
    const protocol = request.headers['sec-websocket-protocol']?.toLowerCase()

    if (!Object.values(CLIENT_TYPE).includes(protocol)) {
      wsClient.close()
      return
    }

    const sessionId = nanoid(8)
    wsMap.set(wsClient, { sessionId, protocol, lastActive: Date.now() })
    console.log(`Connected ${protocol} - sessionId: ${sessionId}`)

    if (protocol === CLIENT_TYPE.SENDER) {
      notifySenderList()
      wsClient.send(JSON.stringify({ type: MESSAGE_TYPE.SENDER_SESSION_ID, sessionId }))
    } else {
      const senders = getSenders()
      wsClient.send(JSON.stringify({ type: MESSAGE_TYPE.RECEIVER_SESSION_ID, sessionId, senders }))
    }

    wsClient.on('message', (message) => {
      const currentClient = wsMap.get(wsClient)
      currentClient.lastActive = Date.now()

      try {
        const data = JSON.parse(message)

        if (DEBUG) console.log(`\nIncoming from ${protocol}:`, data)

        const targetProtocol = getTargetProtocol(protocol)
        const targetSessionId = getTargetSessionId(data, protocol)
        const targetWs = findClient(targetProtocol, targetSessionId)

        if (targetSessionId) {
          pairMap.set(currentClient.sessionId, targetSessionId)
          console.log(`Pairing updated: ${currentClient.sessionId} -> ${targetSessionId}`)
        }

        if (targetWs) {
          targetWs.send(message.toString('utf-8'))
          console.log(`Relayed: ${protocol} -> ${targetProtocol}`)
          return
        }

        sendError(wsClient, protocol, 'Target not found')
      } catch (err) {
        console.error(`Error: ${err.message}\nMessage: ${message}`)
        sendError(wsClient, protocol, err.message)
      }
    })

    wsClient.on('close', () => {
      console.log(`Disconnected ${protocol} - sessionId: ${sessionId}`)
      const targetSessionId = pairMap.get(sessionId)
      if (targetSessionId) {
        const targetProtocol = getTargetProtocol(protocol)
        const targetWs = findClient(targetProtocol, targetSessionId)
        if (targetWs) {
          const closeType = protocol === CLIENT_TYPE.RECEIVER ? MESSAGE_TYPE.SENDER_RECEIVER_CLOSE : MESSAGE_TYPE.RECEIVER_SENDER_CLOSE
          targetWs.send(JSON.stringify({ type: closeType }))
          console.log(`Close notification sent to: ${targetSessionId}`)
        }
        pairMap.delete(sessionId)
        pairMap.delete(targetSessionId)
      }

      wsMap.delete(wsClient)
      if (protocol === CLIENT_TYPE.SENDER) {
        notifySenderList()
      }
    })
  })

  if (!KEEP_ALIVE) {
    // Cleanup of inactive sessions
    setInterval(() => {
      const now = Date.now()
      for (const [ws, client] of wsMap) {
        if (now - client.lastActive > INACTIVE_TIMEOUT) {
          console.log(`Session ${client.sessionId} removed due to inactivity`)
          ws.terminate()
          wsMap.delete(ws)
          pairMap.delete(client.sessionId)
        }
      }
    }, 60 * 1000)
  }
}

// -----------------------------------
// hosts the vrx web resource files
// -----------------------------------
import { fileURLToPath } from 'url'
import path from 'path'
import fs from 'fs'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)
const SRC_DIR = path.join(__dirname, 'vrx')

const VALID_EXTENSIONS = {
  '.html': 'text/html',
  '.ico': 'image/x-icon',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.jpg': 'image/jpeg',
  '.png': 'image/png',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm',
}

function setCORSHeaders(response) {
  response.setHeader('Access-Control-Allow-Origin', '*')
  response.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
  response.setHeader('Access-Control-Allow-Headers', 'Content-Type')
}

function validatePath(pathname) {
  if (pathname.endsWith('/')) {
    pathname += 'index.html'
  }

  const sanitizedPath = path.normalize(pathname).replace(/^(\.\.(\/|\\|$))+/, '')
  const resolvedPath = path.join(SRC_DIR, sanitizedPath)

  if (!resolvedPath.startsWith(SRC_DIR)) {
    return null
  }

  const ext = path.extname(resolvedPath).toLowerCase()
  if (!VALID_EXTENSIONS[ext]) {
    return null
  }

  return resolvedPath
}

function serveFile(filePath, response) {
  fs.access(filePath, fs.constants.F_OK, (err) => {
    if (err) {
      response.writeHead(404)
      response.end('Not Found')
      return
    }

    const ext = path.extname(filePath).toLowerCase()
    const fileStream = fs.createReadStream(filePath)

    response.writeHead(200, { 'Content-Type': VALID_EXTENSIONS[ext] })
    fileStream.pipe(response)
    fileStream.on('error', (err) => {
      console.error('File read error:', err)
      if (!response.headersSent) {
        response.writeHead(500)
        response.end('Internal Server Error')
      }
    })
  })
}

// webHandler -----------------------------------
const webHandler = (request, response) => {
  try {
    setCORSHeaders(response)

    if (request.method === 'OPTIONS') {
      response.writeHead(204)
      response.end()
      return
    }

    const requestUrl = new URL(request.url, `http://${request.headers.host}`)
    const pathname = decodeURIComponent(requestUrl.pathname)
    const filePath = validatePath(pathname)

    if (!filePath) {
      response.writeHead(403)
      response.end('Forbidden')
      return
    }

    serveFile(filePath, response)
  } catch (err) {
    console.error('Request error:', err)
    if (!response.headersSent) {
      response.writeHead(500)
      response.end('Internal Server Error')
    }
  }
}

// -----------------------------------
// create run server
// -----------------------------------
import os from 'os'
import http from 'http'
import https from 'https'

function getLocalIPv4() {
  const interfaces = os.networkInterfaces()
  for (const iface of Object.values(interfaces)) {
    for (const details of iface) {
      if (details.family === 'IPv4' && !details.internal) {
        return details.address
      }
    }
  }
  return 'localhost'
}

const server = TLS
  ? https.createServer(
      {
        key: fs.readFileSync('certificate/server-key.pem'),
        cert: fs.readFileSync('certificate/server-cert.pem'),
      },
      webHandler,
    )
  : http.createServer(webHandler)

signalingHandler(server)

server.listen(TLS ? 443 : 80, () => {
  console.log(`Server is running at: ${TLS ? 'https' : 'http'}://${getLocalIPv4()}`)
})
