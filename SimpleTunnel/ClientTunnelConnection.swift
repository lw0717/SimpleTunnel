/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	This file contains the ClientTunnelConnection class. The ClientTunnelConnection class handles the encapsulation and decapsulation of IP packets in the client side of the SimpleTunnel tunneling protocol.
    该文件包含ClientTunnelConnection类。 ClientTunnelConnection类处理SimpleTunnel隧道协议客户端中IP数据包的封装和解封装。
*/

import Foundation
import SimpleTunnelServices
import NetworkExtension

// MARK: - Protocols

/// The delegate protocol for ClientTunnelConnection.
/// ClientTunnelConnection的委托协议。
protocol ClientTunnelConnectionDelegate {
	/// Handle the connection being opened.
    /// 处理正在打开的连接。
	func tunnelConnectionDidOpen(_ connection: ClientTunnelConnection, configuration: [NSObject: AnyObject])
	/// Handle the connection being closed.
    /// 处理关闭的连接。
	func tunnelConnectionDidClose(_ connection: ClientTunnelConnection, error: NSError?)
}

/// An object used to tunnel IP packets using the SimpleTunnel protocol.
/// 用于使用SimpleTunnel协议隧道传输IP数据包的对象。
class ClientTunnelConnection: Connection {

	// MARK: - Properties

	/// The connection delegate.
    /// 连接委托。
	let delegate: ClientTunnelConnectionDelegate

	/// The flow of IP packets.
    /// IP数据包的流向。
	let packetFlow: NEPacketTunnelFlow

	// MARK: - Initializers

	init(tunnel: ClientTunnel, clientPacketFlow: NEPacketTunnelFlow, connectionDelegate: ClientTunnelConnectionDelegate) {
		delegate = connectionDelegate
		packetFlow = clientPacketFlow
		let newConnectionIdentifier = arc4random()
		super.init(connectionIdentifier: Int(newConnectionIdentifier), parentTunnel: tunnel)
	}

	// MARK: - Interface

	/// Open the connection by sending a "connection open" message to the tunnel server.
    /// 通过向隧道服务器发送“连接打开”消息来打开连接。
	func open() {
		guard let clientTunnel = tunnel as? ClientTunnel else { return }

		let properties = createMessagePropertiesForConnection(identifier, commandType: .open, extraProperties:[
				TunnelMessageKey.TunnelType.rawValue: TunnelLayer.ip.rawValue as AnyObject
			])

		clientTunnel.sendMessage(properties) { error in
			if let error = error {
				self.delegate.tunnelConnectionDidClose(self, error: error as NSError)
			}
		}
	}

	/// Handle packets coming from the packet flow.
    /// 处理来自数据包流的数据包。
	func handlePackets(_ packets: [Data], protocols: [NSNumber]) {
		guard let clientTunnel = tunnel as? ClientTunnel else { return }

		let properties = createMessagePropertiesForConnection(identifier, commandType: .packets, extraProperties:[
				TunnelMessageKey.Packets.rawValue: packets as AnyObject,
				TunnelMessageKey.Protocols.rawValue: protocols as AnyObject
			])

		clientTunnel.sendMessage(properties) { error in
			if let sendError = error {
				self.delegate.tunnelConnectionDidClose(self, error: sendError as NSError?)
				return
			}

			// Read more packets.
            // 读取更多数据包。
			self.packetFlow.readPackets { inPackets, inProtocols in
				self.handlePackets(inPackets, protocols: inProtocols)
			}
		}
	}

	/// Make the initial readPacketsWithCompletionHandler call.
    /// 进行初始的readPacketsWithCompletionHandler调用。
	func startHandlingPackets() {
		packetFlow.readPackets { inPackets, inProtocols in
			self.handlePackets(inPackets, protocols: inProtocols)
		}
	}

	// MARK: - Connection

	/// Handle the event of the connection being established.
    /// 处理正在建立的连接事件。
	override func handleOpenCompleted(_ resultCode: TunnelConnectionOpenResult, properties: [NSObject: AnyObject]) {
		guard resultCode == .success else {
			delegate.tunnelConnectionDidClose(self, error: SimpleTunnelError.badConnection as NSError)
			return
		}

		// Pass the tunnel network settings to the delegate.
        // 将隧道网络设置传递给委托。
		if let configuration = properties[TunnelMessageKey.Configuration.rawValue as NSString] as? [NSObject: AnyObject] {
			delegate.tunnelConnectionDidOpen(self, configuration: configuration)
		}
		else {
			delegate.tunnelConnectionDidOpen(self, configuration: [:])
		}
	}

	/// Send packets to the virtual interface to be injected into the IP stack.
    /// 将数据包发送到虚拟接口以注入IP堆栈。
	override func sendPackets(_ packets: [Data], protocols: [NSNumber]) {
		packetFlow.writePackets(packets, withProtocols: protocols)
	}
}
