/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	This file contains the Connection class. The Connection class is an abstract base class that handles a single flow of network data in the SimpleTunnel tunneling protocol.
    该文件包含Connection类。 Connection类是一个抽象基类，用于处理SimpleTunnel隧道协议中的单个网络数据流。
*/


import Foundation

/// The directions in which a flow can be closed for further data.
/// 进一步数据可关闭流的方向。
public enum TunnelConnectionCloseDirection: Int, CustomStringConvertible {
	case none = 1
	case read = 2
	case write = 3
	case all = 4

	public var description: String {
		switch self {
			case .none: return "none"
			case .read: return "reads"
			case .write: return "writes"
			case .all: return "reads and writes"
		}
	}
}

/// The results of opening a connection.
/// 打开连接的结果。
public enum TunnelConnectionOpenResult: Int {
	case success = 0
	case invalidParam
	case noSuchHost
	case refused
	case timeout
	case internalError
}

/// A logical connection (or flow) of network data in the SimpleTunnel protocol.
/// SimpleTunnel协议中网络数据的逻辑连接（或流）。
open class Connection: NSObject {

	// MARK: - Properties

	/// The connection identifier.
    /// 连接标识符。
	open let identifier: Int

	/// The tunnel that contains the connection.
    /// 包含连接的隧道。
	open var tunnel: Tunnel?

	/// The list of data that needs to be written to the connection when possible.
    /// 在可能的情况下需要写入连接的数据列表。
	let savedData = SavedData()

	/// The direction(s) in which the connection is closed.
    /// 连接关闭的方向。
	var currentCloseDirection = TunnelConnectionCloseDirection.none

	/// Indicates if the tunnel is being used by this connection exclusively.
    /// 表示隧道是否仅由此连接使用。
	let isExclusiveTunnel: Bool

	/// Indicates if the connection cannot be read from.
    /// 表示是否无法读取连接。
	open var isClosedForRead: Bool {
		return currentCloseDirection != .none && currentCloseDirection != .write
	}

	/// Indicates if the connection cannot be written to.
    /// 表示连接是否无法写入。
	open var isClosedForWrite: Bool {
		return currentCloseDirection != .none && currentCloseDirection != .read
	}

	/// Indicates if the connection is fully closed.
    /// 表示连接是否完全关闭。
	open var isClosedCompletely: Bool {
		return currentCloseDirection == .all
	}

	// MARK: - Initializers

	public init(connectionIdentifier: Int, parentTunnel: Tunnel) {
		tunnel = parentTunnel
		identifier = connectionIdentifier
		isExclusiveTunnel = false
		super.init()
		if let t = tunnel {
			// Add this connection to the tunnel's set of connections.
            // 将此连接添加到隧道的一组连接。
			t.addConnection(self)
		}

	}

	public init(connectionIdentifier: Int) {
		isExclusiveTunnel = true
		identifier = connectionIdentifier
	}

	// MARK: - Interface

	/// Set a new tunnel for the connection.
    /// 为连接设置一个新的隧道
	func setNewTunnel(_ newTunnel: Tunnel) {
		tunnel = newTunnel
		if let t = tunnel {
			t.addConnection(self)
		}
	}

	/// Close the connection.
    /// 关闭连接。
	open func closeConnection(_ direction: TunnelConnectionCloseDirection) {
		if direction != .none && direction != currentCloseDirection {
			currentCloseDirection = .all
		}
		else {
			currentCloseDirection = direction
		}

		guard let currentTunnel = tunnel , currentCloseDirection == .all else { return }

		if isExclusiveTunnel {
			currentTunnel.closeTunnel()
		}
		else {
			currentTunnel.dropConnection(self)
			tunnel = nil
		}
	}

	/// Abort the connection.
    /// 中止连接。
	open func abort(_ error: Int = 0) {
		savedData.clear()
	}

	/// Send data on the connection.
    /// 在连接上发送数据。
	open func sendData(_ data: Data) {
	}

	/// Send data and the destination host and port on the connection.
    /// 发送数据以及连接上的目标主机和端口。
	open func sendDataWithEndPoint(_ data: Data, host: String, port: Int) {
	}

	/// Send a list of IP packets and their associated protocols on the connection.
    /// 在连接上发送IP数据包及其相关协议的列表。
	open func sendPackets(_ packets: [Data], protocols: [NSNumber]) {
	}

	/// Send an indication to the remote end of the connection that the caller will not be reading any more data from the connection for a while.
    /// 向连接的远端发送一个指示，呼叫者不会从连接中读取更多的数据一段时间。
	open func suspend() {
	}

	/// Send an indication to the remote end of the connection that the caller is going to start reading more data from the connection.
    /// 向连接的远程端发送一个指示，调用者将开始从连接中读取更多数据。
	open func resume() {
	}

	/// Handle the "open completed" message sent by the SimpleTunnel server.
    /// 处理由SimpleTunnel服务器发送的“打开完成”消息。
	open func handleOpenCompleted(_ resultCode: TunnelConnectionOpenResult, properties: [NSObject: AnyObject]) {
	}
}
