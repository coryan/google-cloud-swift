// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHPACK
import NIOHTTP1
import NIOHTTP2
import NIOPosix
import NIOSSL
import NIOTLS

// MARK: - Test TLS Certificates

enum TestCertificates {
  static let certificatePEM = """
    -----BEGIN CERTIFICATE-----
    MIICmDCCAYACCQCPC8JDqMh1zzANBgkqhkiG9w0BAQsFADANMQswCQYDVQQGEwJ1
    czAgFw0xODEwMzExNTU1MjJaGA8yMTE4MTAwNzE1NTUyMlowDTELMAkGA1UEBhMC
    dXMwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDiC+TGmbSP/nWWN1tj
    yNfnWCU5ATjtIOfdtP6ycx8JSeqkvyNXG21kNUn14jTTU8BglGL2hfVpCbMisUdb
    d3LpP8unSsvlOWwORFOViSy4YljSNM/FNoMtavuITA/sEELYgjWkz2o/uHPZHud9
    +JQwGJgqIlMa3mr2IaaUZlWN3D1u88bzJYhpt3YyxRy9+OEoOKy36KdWwhKzV3S8
    kXb0Y1GbAo68jJ9RfzeLy290mIs9qG2y1CNXWO6sxf6B//LaalizZiCfzYAVKcNR
    9oNYsEJc5KB/+DsAGTzR7mL+oiU4h/vwVb2GTDat5C+PFGi6j1ujxYTRPO538ljg
    dslnAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAFYhA7sw8odOsRO8/DUklBOjPnmn
    a078oSumgPXXw6AgcoAJv/Qthjo6CCEtrjYfcA9jaBw9/Tii7mDmqDRS5c9ZPL8+
    NEPdHjFCFBOEvlL6uHOgw0Z9Wz+5yCXnJ8oNUEgc3H2NbbzJF6sMBXSPtFS2NOK8
    OsAI9OodMrDd6+lwljrmFoCCkJHDEfE637IcsbgFKkzhO/oNCRK6OrudG4teDahz
    Au4LoEYwT730QKC/VQxxEVZobjn9/sTrq9CZlbPYHxX4fz6e00sX7H9i49vk9zQ5
    5qCm9ljhrQPSa42Q62PPE2BEEGSP2KBm0J+H3vlvCD6+SNc/nMZjrRmgjrI=
    -----END CERTIFICATE-----
    """

  static let privateKeyPEM = """
    -----BEGIN PRIVATE KEY-----
    MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQDiC+TGmbSP/nWW
    N1tjyNfnWCU5ATjtIOfdtP6ycx8JSeqkvyNXG21kNUn14jTTU8BglGL2hfVpCbMi
    sUdbd3LpP8unSsvlOWwORFOViSy4YljSNM/FNoMtavuITA/sEELYgjWkz2o/uHPZ
    Hud9+JQwGJgqIlMa3mr2IaaUZlWN3D1u88bzJYhpt3YyxRy9+OEoOKy36KdWwhKz
    V3S8kXb0Y1GbAo68jJ9RfzeLy290mIs9qG2y1CNXWO6sxf6B//LaalizZiCfzYAV
    KcNR9oNYsEJc5KB/+DsAGTzR7mL+oiU4h/vwVb2GTDat5C+PFGi6j1ujxYTRPO53
    8ljgdslnAgMBAAECggEBANZNWFNAnYJ2R5xmVuo/GxFk68Ujd4i4TZpPYbhkk+QG
    g8I0w5htlEQQkVHfZx2CpTvq8feuAH/YhlA5qeD5WaPwq26q5qsmyV6tQGDgb9lO
    w85l6ySZDbwdVOJe2il/MSB6MclSKvTGNm59chJnfHYsmvY3HHq4qsc2F+tRKYMW
    pY75LgEbaTUV69J3cbC1wAeVjv0q/krND+YkhYpTxNZhbazK/FHOCvY+zFu9fg0L
    zpwbn5fb6wIvqG7tXp7koa3QMn64AXmO/fb5mBd8G2vBGYnxwb7Egwdg/3Dw+BXu
    ynQLP7ixWsE2KNfR9Ce1i3YvEo6QDTv2340I3dntxkECgYEA9vdaL4PGyvEbpim4
    kqz1vuug8Iq0nTVDo6jmgH1o+XdcIbW3imXtgi5zUJpj4oDD7/4aufiJZjG64i/v
    phe11xeUvh5QNNOzeMymVDoJut97F97KKKTv7bG8Rpon/WzH2I0SoAkECCwmdWAJ
    H3nvOCnXEkpbCqmIUvHVURPRDn8CgYEA6lCk3EzFQlbXs3Sj5op61R3Mscx7/35A
    eGv5axzbENHt1so+s3Zvyyi1bo4VBcwnKVCvQjmTuLiqrc9VfX8XdbiTUNnEr2u3
    992Ja6DEJTZ9gy5WiviwYnwU2HpjwOVNBb17T0NLoRHkDZ6iXj7NZgwizOki5p3j
    /hS0pObSIRkCgYEAiEdOGNIarHoHy9VR6H5QzR2xHYssx2NRA8p8B4MsnhxjVqaz
    tUcxnJiNQXkwjRiJBrGthdnD2ASxH4dcMsb6rMpyZcbMc5ouewZS8j9khx4zCqUB
    4RPC4eMmBb+jOZEBZlnSYUUYWHokbrij0B61BsTvzUQCoQuUElEoaSkKP3kCgYEA
    mwdqXHvK076jjo9w1drvtEu4IDc8H2oH++TsrEr2QiWzaDZ9z71f8BnqGNCW5jQS
    AQrqOjXgIArGmqMgXB0Xh4LsrUS4Fpx9ptiD0JsYy8pGtuGUzvQFt9OC80ve7kSI
    dnDMwj+zLUmqCrzXjuWcfpUu/UaPGeiDbZuDfcteYhkCgYBLyL5JY7Qd4gVQIhFX
    7Sv3sNJN3KZCQHEzut7IwojaxgpuxiFvgsoXXuYolVCQp32oWbYcE2Yke+hOKsTE
    sCMAWZiSGN2Nrfea730IYAXkUm8bpEd3VxDXEEv13nxVeQof+JGMdlkldFGaBRDU
    oYQsPj00S3/GA9WDapwe81Wl2A==
    -----END PRIVATE KEY-----
    """

  static func makeServerTLSConfiguration() throws -> TLSConfiguration {
    let cert = try NIOSSLCertificate(bytes: Array(certificatePEM.utf8), format: .pem)
    let key = try NIOSSLPrivateKey(bytes: Array(privateKeyPEM.utf8), format: .pem)
    var config = TLSConfiguration.makeServerConfiguration(
      certificateChain: [.certificate(cert)],
      privateKey: .privateKey(key)
    )
    config.applicationProtocols = NIOHTTP2SupportedALPNProtocols
    return config
  }
}

// MARK: - Server Action

enum ServerAction: Sendable {
  case respondThenRstStream(errorCode: HTTP2ErrorCode = .cancel)
  case respondThenGoAway(errorCode: HTTP2ErrorCode = .noError)
}

// MARK: - Mock HTTP/2 Server Stream Handler

private final class MockHTTP2ServerStreamHandler: ChannelInboundHandler {
  typealias InboundIn = HTTP2Frame
  typealias OutboundOut = HTTP2Frame

  private let streamID: HTTP2StreamID
  private let action: ServerAction

  init(streamID: HTTP2StreamID, action: ServerAction) {
    self.streamID = streamID
    self.action = action
  }

  func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    let frame = self.unwrapInboundIn(data)
    switch frame.payload {
    case .headers:
      self.handleRequestHead(context: context)
    default:
      break
    }
  }

  private func handleRequestHead(context: ChannelHandlerContext) {
    switch self.action {
    case .respondThenRstStream(let errorCode):
      // 1. Send response HEADERS frame with endStream: true
      var responseHeaders = HPACKHeaders()
      responseHeaders.add(name: ":status", value: "200")
      let headersFrame = HTTP2Frame(
        streamID: self.streamID,
        payload: .headers(.init(headers: responseHeaders, endStream: true))
      )
      context.writeAndFlush(self.wrapOutboundOut(headersFrame), promise: nil)

      // 2. Immediately inject RST_STREAM on parent connection channel for this streamID
      let parentChannel = context.channel.parent
      let streamID = self.streamID
      let rstFrame = HTTP2Frame(streamID: streamID, payload: .rstStream(errorCode))
      parentChannel?.writeAndFlush(rstFrame, promise: nil)

    case .respondThenGoAway(let errorCode):
      // 1. Send response HEADERS frame with endStream: true
      var responseHeaders = HPACKHeaders()
      responseHeaders.add(name: ":status", value: "200")
      let headersFrame = HTTP2Frame(
        streamID: self.streamID,
        payload: .headers(.init(headers: responseHeaders, endStream: true))
      )
      context.writeAndFlush(self.wrapOutboundOut(headersFrame), promise: nil)

      // 2. Immediately inject GOAWAY on parent connection channel
      let parentChannel = context.channel.parent
      let streamID = self.streamID
      let goAwayFrame = HTTP2Frame(
        streamID: .rootStream,
        payload: .goAway(lastStreamID: streamID, errorCode: errorCode, opaqueData: nil)
      )
      parentChannel?.writeAndFlush(goAwayFrame, promise: nil)
    }
  }
}

// MARK: - Minimal HTTP/2 Test Server

final class MinimalHTTP2TestServer: @unchecked Sendable {
  private let group: EventLoopGroup
  private var serverChannel: Channel?
  let port: Int
  let host: String = "127.0.0.1"

  var url: String {
    "https://\(host):\(port)"
  }

  init(action: ServerAction = .respondThenRstStream()) throws {
    self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let tlsConfig = try TestCertificates.makeServerTLSConfiguration()
    let sslContext = try NIOSSLContext(configuration: tlsConfig)

    let serverBootstrap = ServerBootstrap(group: self.group)
      .serverChannelOption(ChannelOptions.backlog, value: 256)
      .serverChannelOption(
        ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1
      )
      .childChannelInitializer { channel in
        let sslHandler = NIOSSLServerHandler(context: sslContext)
        let alpnHandler = ApplicationProtocolNegotiationHandler { result in
          switch result {
          case .negotiated("h2"):
            let http2Handler = NIOHTTP2Handler(mode: .server)
            let multiplexer = HTTP2StreamMultiplexer(
              mode: .server,
              channel: channel,
              inboundStreamStateInitializer: { (streamChannel: Channel, streamID: HTTP2StreamID) in
                streamChannel.eventLoop.makeCompletedFuture {
                  try streamChannel.pipeline.syncOperations.addHandler(
                    MockHTTP2ServerStreamHandler(streamID: streamID, action: action)
                  )
                }
              }
            )
            return channel.pipeline.addHandlers([http2Handler, multiplexer])

          case .negotiated, .fallback:
            channel.close(promise: nil)
            return channel.eventLoop.makeFailedFuture(NIOHTTP2Errors.invalidALPNToken())
          }
        }
        return channel.pipeline.addHandlers([sslHandler, alpnHandler])
      }

    let channel = try serverBootstrap.bind(host: self.host, port: 0).wait()
    self.serverChannel = channel
    self.port = Int(channel.localAddress!.port!)
  }

  func shutdown() async throws {
    try await self.serverChannel?.close()
    try await self.group.shutdownGracefully()
  }

  deinit {
    try? self.group.syncShutdownGracefully()
  }
}

@main
struct HTTP2ServerCrashRepro {
  static func main() async throws {
    print("=== Starting HTTP2ServerCrashRepro ===")
    print("Testing isolated HTTP/2 server repro without external Google Cloud calls...")

    let mode = CommandLine.arguments.dropFirst().first ?? "rst"
    let action: ServerAction =
      mode == "goaway"
      ? .respondThenGoAway(errorCode: .noError)
      : .respondThenRstStream(errorCode: .cancel)
    print("Configured server action: \(action)")

    let server = try MinimalHTTP2TestServer(action: action)
    defer {
      Task { try? await server.shutdown() }
    }
    print("Mock HTTP/2 Server listening at \(server.url)")

    var config = HTTPClient.Configuration()
    config.tlsConfiguration = .clientDefault
    config.tlsConfiguration?.certificateVerification = .none
    config.httpVersion = .automatic

    let client = HTTPClient(eventLoopGroupProvider: .singleton, configuration: config)
    defer {
      Task { try? await client.shutdown() }
    }

    // Streaming request body that delivers one chunk, then stays open long enough
    // for the server to return 200 OK + END_STREAM and RST_STREAM.
    let stream = AsyncStream<NIOCore.ByteBuffer> { continuation in
      Task {
        var buf = ByteBufferAllocator().buffer(capacity: 1024)
        buf.writeRepeatingByte(0x42, count: 1024)
        continuation.yield(buf)
        // Wait so the body stream does not finish before server responds and sends RST_STREAM
        try? await Task.sleep(for: .milliseconds(500))
        continuation.yield(buf)
        continuation.finish()
      }
    }

    var request = HTTPClientRequest(url: "\(server.url)/test")
    request.method = .POST
    request.headers.add(name: "Content-Type", value: "application/octet-stream")
    request.body = .stream(stream, length: .unknown)

    print("Sending streaming request to mock server...")
    do {
      let response = try await client.execute(request, timeout: .seconds(5))
      print("Response received: \(response.status)")
      for try await chunk in response.body {
        print("Received \(chunk.readableBytes) bytes from response body")
      }
      // Wait for any trailing RST_STREAM handling on the channel
      try await Task.sleep(for: .milliseconds(200))
      print("Request completed normally.")
    } catch {
      print("Caught expected/unexpected error: \(error)")
    }
  }
}
