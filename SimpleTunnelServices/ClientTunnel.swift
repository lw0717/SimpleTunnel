/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	This file contains the ClientTunnel class. The ClientTunnel class implements the client side of the SimpleTunnel tunneling protocol.
    该文件包含ClientTunnel类。 ClientTunnel类实现SimpleTunnel隧道协议的客户端。
*/

import Foundation
import NetworkExtension

/// Make NEVPNStatus convertible to a string
/// 使NEVPNStatus可转换为字符串
extension NWTCPConnectionState: CustomStringConvertible {
	public var description: String {
		switch self {
			case .cancelled: return "Cancelled"
			case .connected: return "Connected"
			case .connecting: return "Connecting"
			case .disconnected: return "Disconnected"
			case .invalid: return "Invalid"
			case .waiting: return "Waiting"
		}
	}
}

/// The client-side implementation of the SimpleTunnel protocol.
/// SimpleTunnel协议的客户端实现
open class ClientTunnel: Tunnel {

	// MARK: - Properties

	/// The tunnel connection.
    ///隧道连接。
	open var connection: NWTCPConnection?

	/// The last error that occurred on the tunnel.
    /// 隧道发生的最后一个错误。
	open var lastError: NSError?

	/// The previously-received incomplete message data.
    /// 先前收到的不完整的消息数据。
	var previousData: NSMutableData?

	/// The address of the tunnel server.
    /// 隧道服务器的地址。
	open var remoteHost: String?

	// MARK: - Interface

	/// Start the TCP connection to the tunnel server.
    /// 启动到隧道服务器的TCP连接。
	open func startTunnel(_ provider: NETunnelProvider) -> SimpleTunnelError? {

		guard let serverAddress = provider.protocolConfiguration.serverAddress else {
			return .badConfiguration
		}

		let endpoint: NWEndpoint

		if let colonRange = serverAddress.rangeOfCharacter(from: CharacterSet(charactersIn: ":"), options: [], range: nil) {
			// The server is specified in the configuration as <host>:<port>.
            // 服务器在配置中被指定为<host>：<port>。
            let hostname = serverAddress.substring(with: serverAddress.startIndex..<colonRange.lowerBound)
			let portString = serverAddress.substring(with: serverAddress.index(after: colonRange.lowerBound)..<serverAddress.endIndex)

			guard !hostname.isEmpty && !portString.isEmpty else {
				return .badConfiguration
			}

			endpoint = NWHostEndpoint(hostname:hostname, port:portString)
		}
		else {
			// The server is specified in the configuration as a Bonjour service name.
            // 服务器在配置中被指定为Bonjour服务名称。
			endpoint = NWBonjourServiceEndpoint(name: serverAddress, type:Tunnel.serviceType, domain:Tunnel.serviceDomain)
		}

		// Kick off the connection to the server.
        // 启动与服务器的连接。
		connection = provider.createTCPConnection(to: endpoint, enableTLS:false, tlsParameters:nil, delegate:nil)

		// Register for notificationes when the connection status changes.
        // 在连接状态改变时注册通知。
		connection!.addObserver(self, forKeyPath: "state", options: .initial, context: &connection)

		return nil
	}

	/// Close the tunnel.
    /// 关闭隧道。
	open func closeTunnelWithError(_ error: NSError?) {
		lastError = error
		closeTunnel()
	}

	/// Read a SimpleTunnel packet from the tunnel connection.
    /// 从隧道连接读取SimpleTunnel数据包。
	func readNextPacket() {
		guard let targetConnection = connection else {
			closeTunnelWithError(SimpleTunnelError.badConnection as NSError)
			return
		}

		// First, read the total length of the packet.
        // 首先读取数据包的总长度。
		targetConnection.readMinimumLength(MemoryLayout<UInt32>.size, maximumLength: MemoryLayout<UInt32>.size) { data, error in
			if let readError = error {
				simpleTunnelLog("Got an error on the tunnel connection: \(readError)")
				self.closeTunnelWithError(readError as NSError?)
				return
			}

			let lengthData = data

			guard lengthData!.count == MemoryLayout<UInt32>.size else {
				simpleTunnelLog("Length data length (\(lengthData!.count)) != sizeof(UInt32) (\(MemoryLayout<UInt32>.size)")
				self.closeTunnelWithError(SimpleTunnelError.internalError as NSError)
				return
			}

			var totalLength: UInt32 = 0
			(lengthData as! NSData).getBytes(&totalLength, length: MemoryLayout<UInt32>.size)

			if totalLength > UInt32(Tunnel.maximumMessageSize) {
				simpleTunnelLog("Got a length that is too big: \(totalLength)")
				self.closeTunnelWithError(SimpleTunnelError.internalError as NSError)
				return
			}

			totalLength -= UInt32(MemoryLayout<UInt32>.size)

			// Second, read the packet payload.
            // 其次，读取数据包有效载荷。
			targetConnection.readMinimumLength(Int(totalLength), maximumLength: Int(totalLength)) { data, error in
				if let payloadReadError = error {
					simpleTunnelLog("Got an error on the tunnel connection: \(payloadReadError)")
					self.closeTunnelWithError(payloadReadError as NSError?)
					return
				}

				let payloadData = data

				guard payloadData!.count == Int(totalLength) else {
					simpleTunnelLog("Payload data length (\(payloadData!.count)) != payload length (\(totalLength)")
					self.closeTunnelWithError(SimpleTunnelError.internalError as NSError)
					return
				}

				_ = self.handlePacket(payloadData!)

				self.readNextPacket()
			}
		}
	}

	/// Send a message to the tunnel server.
    /// 发送消息到隧道服务器。
	open func sendMessage(_ messageProperties: [String: AnyObject], completionHandler: @escaping (Error?) -> Void) {
		guard let messageData = serializeMessage(messageProperties) else {
			completionHandler(SimpleTunnelError.internalError as NSError)
			return
		}

		connection?.write(messageData, completionHandler: completionHandler)
	}

	// MARK: - NSObject

	/// Handle changes to the tunnel connection state.
    /// 处理对隧道连接状态的更改。
	open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
		guard keyPath == "state" && context?.assumingMemoryBound(to: Optional<NWTCPConnection>.self).pointee == connection else {
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
			return
		}

		simpleTunnelLog("Tunnel connection state changed to \(connection!.state)")

		switch connection!.state {
			case .connected:
				if let remoteAddress = self.connection!.remoteAddress as? NWHostEndpoint {
					remoteHost = remoteAddress.hostname
				}

				// Start reading messages from the tunnel connection.
                // 开始从隧道连接读取消息。
				readNextPacket()

				// Let the delegate know that the tunnel is open
                //  让委托人知道隧道是开放的
				delegate?.tunnelDidOpen(self)

			case .disconnected:
				closeTunnelWithError(connection!.error as NSError?)

			case .cancelled:
				connection!.removeObserver(self, forKeyPath:"state", context:&connection)
				connection = nil
				delegate?.tunnelDidClose(self)

			default:
				break
		}
	}

	// MARK: - Tunnel

	/// Close the tunnel.
    /// 关闭隧道。
	override open func closeTunnel() {
		super.closeTunnel()
		// Close the tunnel connection.
		if let TCPConnection = connection {
			TCPConnection.cancel()
		}

	}

	/// Write data to the tunnel connection.
    /// 将数据写入隧道连接。
	override func writeDataToTunnel(_ data: Data, startingAtOffset: Int) -> Int {
		connection?.write(data) { error in
			if error != nil {
				self.closeTunnelWithError(error as NSError?)
			}
		}
		return data.count
	}

	/// Handle a message received from the tunnel server.
    /// 处理从隧道服务器收到的消息。
	override func handleMessage(_ commandType: TunnelCommand, properties: [String: AnyObject], connection: Connection?) -> Bool {
		var success = true

		switch commandType {
			case .openResult:
				// A logical connection was opened successfully.
                // 逻辑连接已成功打开。
				guard let targetConnection = connection,
					let resultCodeNumber = properties[TunnelMessageKey.ResultCode.rawValue] as? Int,
					let resultCode = TunnelConnectionOpenResult(rawValue: resultCodeNumber)
					else
				{
					success = false
					break
				}

				targetConnection.handleOpenCompleted(resultCode, properties:properties as [NSObject : AnyObject])

			case .fetchConfiguration:
				guard let configuration = properties[TunnelMessageKey.Configuration.rawValue] as? [String: AnyObject]
					else { break }

				delegate?.tunnelDidSendConfiguration(self, configuration: configuration)
			
			default:
				simpleTunnelLog("Tunnel received an invalid command")
				success = false
		}
		return success
	}

	/// Send a FetchConfiguration message on the tunnel connection.
    /// 在隧道连接上发送FetchConfiguration消息。
	open func sendFetchConfiguation() {
		let properties = createMessagePropertiesForConnection(0, commandType: .fetchConfiguration)
		if !sendMessage(properties) {
			simpleTunnelLog("Failed to send a fetch configuration message")
		}
	}
}
