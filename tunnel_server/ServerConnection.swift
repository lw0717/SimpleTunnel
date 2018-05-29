/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	This file contains the ServerConnection class. The ServerConnection class encapsulates and decapsulates a stream of network data in the server side of the SimpleTunnel tunneling protocol.
    该文件包含ServerConnection类。 ServerConnection类在SimpleTunnel隧道协议的服务器端封装和解封装网络数据流。
*/

import Foundation

/// An object representing the server side of a logical flow of TCP network data in the SimpleTunnel tunneling protocol.
/// 表示SimpleTunnel隧道协议中TCP网络数据的逻辑流的服务器端的对象。
class ServerConnection: Connection, StreamDelegate {

	// MARK: - Properties

	/// The stream used to read network data from the connection.
    /// 用于从连接读取网络数据的流。
	var readStream: InputStream?

	/// The stream used to write network data to the connection.
    /// 用于将网络数据写入连接的流。
	var writeStream: OutputStream?

	// MARK: - Interface

	/// Open the connection to a host and port.
    /// 打开与主机和端口的连接。
	func open(host: String, port: Int) -> Bool {
		simpleTunnelLog("Connection \(identifier) connecting to \(host):\(port)")
		
		Stream.getStreamsToHost(withName: host, port: port, inputStream: &readStream, outputStream: &writeStream)

		guard let newReadStream = readStream, let newWriteStream = writeStream else {
			return false
		}

		for stream in [newReadStream, newWriteStream] {
			stream.delegate = self
			stream.open()
			stream.schedule(in: .main, forMode: RunLoopMode.defaultRunLoopMode)
		}

		return true
	}

	// MARK: - Connection

	/// Close the connection.
    /// 关闭连接。
	override func closeConnection(_ direction: TunnelConnectionCloseDirection) {
		super.closeConnection(direction)
		
		if let stream = writeStream, isClosedForWrite && savedData.isEmpty {
			if let error = stream.streamError {
				simpleTunnelLog("Connection \(identifier) write stream error: \(error)")
			}

			stream.remove(from: .main, forMode: RunLoopMode.defaultRunLoopMode)
			stream.close()
			stream.delegate = nil
			writeStream = nil
		}

		if let stream = readStream, isClosedForRead {
			if let error = stream.streamError {
				simpleTunnelLog("Connection \(identifier) read stream error: \(error)")
			}

			stream.remove(from: .main, forMode: RunLoopMode.defaultRunLoopMode)
			stream.close()
			stream.delegate = nil
			readStream = nil
		}
	}

	/// Abort the connection.
    /// 中止连接。
	override func abort(_ error: Int = 0) {
		super.abort(error)
		closeConnection(.all)
	}

	/// Stop reading from the connection.
    /// 停止从连接读取。
	override func suspend() {
		if let stream = readStream {
			stream.remove(from: .main, forMode: RunLoopMode.defaultRunLoopMode)
		}
	}

	/// Start reading from the connection.
    /// 从连接开始读取。
	override func resume() {
		if let stream = readStream {
			stream.schedule(in: .main, forMode: RunLoopMode.defaultRunLoopMode)
		}
	}

	/// Send data over the connection.
    /// 通过连接发送数据。
	override func sendData(_ data: Data) {
		guard let stream = writeStream else { return }
		var written = 0

		if savedData.isEmpty {
			written = writeData(data as Data, toStream: stream, startingAtOffset: 0)

			if written < data.count {
				// We could not write all of the data to the connection. Tell the client to stop reading data for this connection.
                // 我们无法将所有数据写入连接。 告诉客户停止读取此连接的数据。
				stream.remove(from: .main, forMode: RunLoopMode.defaultRunLoopMode)
				tunnel?.sendSuspendForConnection(identifier)
			}
		}

		if written < data.count {
			savedData.append(data as Data, offset: written)
		}
	}

	// MARK: - NSStreamDelegate

	/// Handle an event on a stream.
    /// 处理流中的事件。
	func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		switch aStream {

			case writeStream!:
				switch eventCode {
					case [.hasSpaceAvailable]:
						if !savedData.isEmpty {
							guard savedData.writeToStream(writeStream!) else {
								tunnel?.sendCloseType(.all, forConnection: identifier)
								abort()
								break
							}

							if savedData.isEmpty {
								writeStream?.remove(from: .main, forMode: RunLoopMode.defaultRunLoopMode)
								if isClosedForWrite {
									closeConnection(.write)
								}
								else {
									tunnel?.sendResumeForConnection(identifier)
								}
							}
						}
						else {
							writeStream?.remove(from: .main, forMode: RunLoopMode.defaultRunLoopMode)
						}

					case [.endEncountered]:
						tunnel?.sendCloseType(.read, forConnection: identifier)
						closeConnection(.write)

					case [.errorOccurred]:
						tunnel?.sendCloseType(.all, forConnection: identifier)
						abort()

					default:
						break
				}

			case readStream!:
				switch eventCode {
					case [.hasBytesAvailable]:
						if let stream = readStream {
							while stream.hasBytesAvailable {
								var readBuffer = [UInt8](repeating: 0, count: 8192)
								let bytesRead = stream.read(&readBuffer, maxLength: readBuffer.count)

								if bytesRead < 0 {
									abort()
									break
								}

								if bytesRead == 0 {
									simpleTunnelLog("\(identifier): got EOF, sending close")
									tunnel?.sendCloseType(.write, forConnection: identifier)
									closeConnection(.read)
									break
								}

								let readData = NSData(bytes: readBuffer, length: bytesRead)
								tunnel?.sendData(readData as Data, forConnection: identifier)
							}
						}

					case [.endEncountered]:
						tunnel?.sendCloseType(.write, forConnection: identifier)
						closeConnection(.read)

					case [.errorOccurred]:
						if let serverTunnel = tunnel as? ServerTunnel {
							serverTunnel.sendOpenResultForConnection(connectionIdentifier: identifier, resultCode: .timeout)
							serverTunnel.sendCloseType(.all, forConnection: identifier)
							abort()
						}

					case [.openCompleted]:
						if let serverTunnel = tunnel as? ServerTunnel {
							serverTunnel.sendOpenResultForConnection(connectionIdentifier: identifier, resultCode: .success)
						}

					default:
						break
				}
			default:
				break
		}
	}
}
