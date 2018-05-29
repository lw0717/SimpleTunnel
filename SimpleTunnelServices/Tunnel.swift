/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	This file contains the Tunnel class. The Tunnel class is an abstract base class that implements all of the common code between the client and server sides of the SimpleTunnel tunneling protocol.
    该文件包含Tunnel类。 Tunnel类是抽象基类，实现SimpleTunnel隧道协议的客户端和服务器端之间的所有通用代码。
*/

import Foundation

/// Command types in the SimpleTunnel protocol
/// SimpleTunnel协议中的命令类型
public enum TunnelCommand: Int, CustomStringConvertible {
	case data = 1
	case suspend = 2
	case resume = 3
	case close = 4
	case dns = 5
	case open = 6
	case openResult = 7
	case packets = 8
	case fetchConfiguration = 9

	public var description: String {
		switch self {
			case .data: return "Data"
			case .suspend: return "Suspend"
			case .resume: return "Resume"
			case .close: return "Close"
			case .dns: return "DNS"
			case .open: return "Open"
			case .openResult: return "OpenResult"
			case .packets: return "Packets"
			case .fetchConfiguration: return "FetchConfiguration"
		}
	}
}

/// Keys in SimpleTunnel message dictionaries.
/// SimpleTunnel消息字典中的密钥。
public enum TunnelMessageKey: String {
	case Identifier = "identifier"
	case Command = "command"
	case Data = "data"
	case CloseDirection = "close-type"
	case DNSPacket = "dns-packet"
	case DNSPacketSource = "dns-packet-source"
	case ResultCode = "result-code"
	case TunnelType = "tunnel-type"
	case Host = "host"
	case Port = "port"
	case Configuration = "configuration"
	case Packets = "packets"
	case Protocols = "protocols"
	case AppProxyFlowType = "app-proxy-flow-type"
}

/// The layer at which the tunnel tunnels traffic.
/// 隧道隧道传输的层。
public enum TunnelLayer: Int {
	case app = 0
	case ip = 1
}

/// For App Layer tunnel, the type of socket being tunneled.
/// 对于App Layer隧道，隧道的套接字类型。
public enum AppProxyFlowKind: Int {
    case tcp = 1
    case udp = 3
}

/// The tunnel delegate protocol.
/// 隧道委托协议。
public protocol TunnelDelegate: class {
	func tunnelDidOpen(_ targetTunnel: Tunnel)
	func tunnelDidClose(_ targetTunnel: Tunnel)
	func tunnelDidSendConfiguration(_ targetTunnel: Tunnel, configuration: [String: AnyObject])
}

/// The base class that implements common behavior and data structure for both sides of the SimpleTunnel protocol.
/// 为SimpleTunnel协议的两端实现公共行为和数据结构的基类。
open class Tunnel: NSObject {

	// MARK: - Properties

	/// The tunnel delegate.
    /// 隧道委托。
    open weak var delegate: TunnelDelegate?

	/// The current set of logical connections open within the tunnel.
    /// 在隧道内打开当前的一组逻辑连接。
    var connections = [Int: Connection]()

	/// The list of data that needs to be written to the tunnel connection when possible.
    /// 如果可能的话，需要写入隧道连接的数据列表。
	let savedData = SavedData()

	/// The SimpleTunnel Bonjour service type.
    /// SimpleTunnel Bonjour服务类型。
	class var serviceType: String { return "_tunnelserver._tcp" }

	/// The SimpleTunnel Bonjour service domain.
    /// SimpleTunnel Bonjour服务域。
	class var serviceDomain: String { return "local" }

	/// The maximum size of a SimpleTunnel message.
    /// SimpleTunnel消息的最大大小。
	class var maximumMessageSize: Int { return 128 * 1024 }

	/// The maximum size of a single tunneled IP packet.
    /// 单个隧道IP数据包的最大大小。
	class var packetSize: Int { return 8192 }

	/// The maximum number of IP packets in a single SimpleTunnel data message.
    /// 单个SimpleTunnel数据消息中IP数据包的最大数量。
	class var maximumPacketsPerMessage: Int { return 32 }

	/// A list of all tunnels.
    /// 所有隧道的列表。
	static var allTunnels = [Tunnel]()

	// MARK: - Initializers

	override public init() {
		super.init()
		Tunnel.allTunnels.append(self)
	}

	// MARK: - Interface

	/// Close the tunnel.
    /// 关闭隧道。
	func closeTunnel() {
		for connection in connections.values {
			connection.tunnel = nil
			connection.abort()
		}
		connections.removeAll(keepingCapacity: false)
		
		savedData.clear()

		if let index = Tunnel.allTunnels.index(where: { return $0 === self }) {
			Tunnel.allTunnels.remove(at: index)
		}
	}
	
	/// Add a connection to the set.
    /// 向该集合添加连接。
	func addConnection(_ connection: Connection) {
		connections[connection.identifier] = connection
	}

	/// Remove a connection from the set.
    /// 从集合中删除连接。
	func dropConnection(_ connection: Connection) {
		connections.removeValue(forKey: connection.identifier)
	}

	/// Close all open tunnels.
    /// 关闭所有打开的隧道。
	class func closeAll() {
		for tunnel in Tunnel.allTunnels {
			tunnel.closeTunnel()
		}
		Tunnel.allTunnels.removeAll(keepingCapacity: false)
	}

	/// Write some data (i.e., a serialized message) to the tunnel.
    /// 将一些数据（即序列化消息）写入隧道。
    func writeDataToTunnel(_ data: Data, startingAtOffset: Int) -> Int {
        simpleTunnelLog("writeDataToTunnel called on abstract base class")
        return -1
    }

	/// Serialize a message
    /// 序列化消息
	func serializeMessage(_ messageProperties: [String: AnyObject]) -> Data? {
		var messageData: NSMutableData?
		do {
			/*
			 * Message format:
			 * 
			 *  0 1 2 3 4 ... Length
			 * +-------+------------+
             * |Length | Payload    |
             * +-------+------------+
			 *
			 */
			let payload = try PropertyListSerialization.data(fromPropertyList: messageProperties, format: .binary, options: 0)
			var totalLength: UInt32 = UInt32(payload.count + MemoryLayout<UInt32>.size)
			messageData = NSMutableData(capacity: Int(totalLength))
			messageData?.append(&totalLength, length: MemoryLayout<UInt32>.size)
			messageData?.append(payload)
		}
		catch {
			simpleTunnelLog("Failed to create a data object from a message property list: \(messageProperties)")
		}
		return messageData as Data?
	}

	/// Send a message on the tunnel connection.
    /// 在隧道连接上发送消息。
	func sendMessage(_ messageProperties: [String: AnyObject]) -> Bool {
		var written: Int = 0

        guard let messageData = serializeMessage(messageProperties) else {
            simpleTunnelLog("Failed to create message data")
            return false
        }
                
        if savedData.isEmpty {
			// There is nothing queued up to be sent, to directly write to the tunnel.
            // 没有排队等待发送，直接写入隧道。
            written = writeDataToTunnel(messageData, startingAtOffset:0)
            if written < 0 {
                closeTunnel()
            }
        }

		// If not all of the data was written, save the message data to be sent when possible.
        // 如果不是所有数据都被写入，则尽可能保存要发送的消息数据。
        if written < messageData.count {
            savedData.append(messageData, offset: written)

			// Suspend all connections until the saved data can be written.
            // 暂停所有连接，直到可以写入保存的数据。
            for connection in connections.values {
                connection.suspend()
            }
        }
            
        return true
	}

	/// Send a Data message on the tunnel connection.
    /// 在隧道连接上发送数据消息。
	func sendData(_ data: Data, forConnection connectionIdentifier: Int) {
		let properties = createMessagePropertiesForConnection(connectionIdentifier, commandType: .data, extraProperties:[
				TunnelMessageKey.Data.rawValue : data as AnyObject
			])

		if !sendMessage(properties) {
			simpleTunnelLog("Failed to send a data message for connection \(connectionIdentifier)")
		}
	}

	/// Send a Data message with an associated endpoint.
    /// 发送数据消息和关联的端点。
	func sendDataWithEndPoint(_ data: Data, forConnection connectionIdentifier: Int, host: String, port: Int ) {
		let properties = createMessagePropertiesForConnection(connectionIdentifier, commandType: .data, extraProperties:[
				TunnelMessageKey.Data.rawValue: data as AnyObject,
				TunnelMessageKey.Host.rawValue: host as AnyObject,
				TunnelMessageKey.Port.rawValue: port as AnyObject
			])

		if !sendMessage(properties) {
			simpleTunnelLog("Failed to send a data message for connection \(connectionIdentifier)")
		}
	}

	/// Send a Suspend message on the tunnel connection.
    /// 在隧道连接上发送挂起消息。
	func sendSuspendForConnection(_ connectionIdentifier: Int) {
		let properties = createMessagePropertiesForConnection(connectionIdentifier, commandType: .suspend)
		if !sendMessage(properties) {
			simpleTunnelLog("Failed to send a suspend message for connection \(connectionIdentifier)")
		}
	}

	/// Send a Resume message on the tunnel connection.
    /// 在隧道连接上发送恢复消息。
	func sendResumeForConnection(_ connectionIdentifier: Int) {
		let properties = createMessagePropertiesForConnection(connectionIdentifier, commandType: .resume)
		if !sendMessage(properties) {
			simpleTunnelLog("Failed to send a resume message for connection \(connectionIdentifier)")
		}
	}

	/// Send a Close message on the tunnel connection.
    /// 在隧道连接上发送关闭消息。
	open func sendCloseType(_ type: TunnelConnectionCloseDirection, forConnection connectionIdentifier: Int) {
		let properties = createMessagePropertiesForConnection(connectionIdentifier, commandType: .close, extraProperties:[
				TunnelMessageKey.CloseDirection.rawValue: type.rawValue as AnyObject
			])
			
		if !sendMessage(properties) {
			simpleTunnelLog("Failed to send a close message for connection \(connectionIdentifier)")
		}
	}

	/// Send a Packets message on the tunnel connection.
    /// 在隧道连接上发送数据包消息。
	func sendPackets(_ packets: [Data], protocols: [NSNumber], forConnection connectionIdentifier: Int) {
		let properties = createMessagePropertiesForConnection(connectionIdentifier, commandType: .packets, extraProperties:[
				TunnelMessageKey.Packets.rawValue: packets as AnyObject,
				TunnelMessageKey.Protocols.rawValue: protocols as AnyObject
			])

		if !sendMessage(properties) {
			simpleTunnelLog("Failed to send a packet message")
		}
	}

	/// Process a message payload.
    /// 处理消息负载。
	func handlePacket(_ packetData: Data) -> Bool {
		let properties: [String: AnyObject]
		do {
			properties = try PropertyListSerialization.propertyList(from: packetData, options: PropertyListSerialization.MutabilityOptions(), format: nil) as! [String: AnyObject]
		}
		catch {
			simpleTunnelLog("Failed to create the message properties from the packet")
			return false
		}

		guard let command = properties[TunnelMessageKey.Command.rawValue] as? Int else {
			simpleTunnelLog("Message command type is missing")
			return false
		}
		guard let commandType = TunnelCommand(rawValue: command) else {
			simpleTunnelLog("Message command type \(command) is invalid")
			return false
		}
		var connection: Connection?

		if let connectionIdentifierNumber = properties[TunnelMessageKey.Identifier.rawValue] as? Int, commandType != .open && commandType != .dns
		{
			connection = connections[connectionIdentifierNumber]
		}

		guard let targetConnection = connection else {
			return handleMessage(commandType, properties: properties, connection: connection)
		}

		switch commandType {
			case .data:
				guard let data = properties[TunnelMessageKey.Data.rawValue] as? Data else { break }

				/* check if the message has properties for host and port */
                /* 检查消息是否具有主机和端口的属性 */
				if let host = properties[TunnelMessageKey.Host.rawValue] as? String,
					let port = properties[TunnelMessageKey.Port.rawValue] as? Int
				{
					simpleTunnelLog("Received data for connection \(connection?.identifier) from \(host):\(port)")
					/* UDP case : send peer's address along with data */
                    /* UDP情况：发送对方地址和数据 */
					targetConnection.sendDataWithEndPoint(data, host: host, port: port)
				}
				else {
					targetConnection.sendData(data)
				}

			case .suspend:
				targetConnection.suspend()

			case .resume:
				targetConnection.resume()

			case .close:
				if let closeDirectionNumber = properties[TunnelMessageKey.CloseDirection.rawValue] as? Int,
					let closeDirection = TunnelConnectionCloseDirection(rawValue: closeDirectionNumber)
				{
					simpleTunnelLog("\(connection?.identifier): closing \(closeDirection)")
					targetConnection.closeConnection(closeDirection)
				} else {
					simpleTunnelLog("\(connection?.identifier): closing reads and writes")
					targetConnection.closeConnection(.all)
				}

			case .packets:
				if let packets = properties[TunnelMessageKey.Packets.rawValue] as? [Data],
					let protocols = properties[TunnelMessageKey.Protocols.rawValue] as? [NSNumber], packets.count == protocols.count
				{
					targetConnection.sendPackets(packets, protocols: protocols)
				}

			default:
				return handleMessage(commandType, properties: properties, connection: connection)
		}

		return true
	}

	/// Handle a recieved message.
    /// 处理收到的消息。
	func handleMessage(_ command: TunnelCommand, properties: [String: AnyObject], connection: Connection?) -> Bool {
		simpleTunnelLog("handleMessage called on abstract base class")
		return false
	}
}
