/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	This file contains some utility classes and functions used by various parts of the SimpleTunnel project.
    该文件包含SimpleTunnel项目各个部分使用的一些实用程序类和函数。
*/

import Foundation
import Darwin

/// SimpleTunnel errors
/// SimpleTunnel错误
public enum SimpleTunnelError: Error {
    case badConfiguration
    case badConnection
	case internalError
}

/// A queue of blobs of data
/// 数据二进制块队列
class SavedData {

	// MARK: - Properties

	/// Each item in the list contains a data blob and an offset (in bytes) within the data blob of the data that is yet to be written.
    /// 列表中的每个项目都包含一个数据blob和尚未写入的数据数据blob中的偏移量（以字节为单位）。
	var chain = [(data: Data, offset: Int)]()

	/// A convenience property to determine if the list is empty.
    /// 确定列表是否为空的便利属性。
	var isEmpty: Bool {
		return chain.isEmpty
	}

	// MARK: - Interface

	/// Add a data blob and offset to the end of the list.
    /// 将数据blob和偏移量添加到列表的末尾。
	func append(_ data: Data, offset: Int) {
		chain.append(data: data, offset: offset)
	}

	/// Write as much of the data in the list as possible to a stream
    /// 将尽可能多的数据写入列表中
	func writeToStream(_ stream: OutputStream) -> Bool {
		var result = true
		var stopIndex: Int?

		for (chainIndex, record) in chain.enumerated() {
			let written = writeData(record.data, toStream: stream, startingAtOffset:record.offset)
			if written < 0 {
				result = false
				break
			}
			if written < (record.data.count - record.offset) {
				// Failed to write all of the remaining data in this blob, update the offset.
                // 无法将所有剩余数据写入此Blob中，更新偏移量。
				chain[chainIndex] = (record.data, record.offset + written)
				stopIndex = chainIndex
				break
			}
		}

		if let removeEnd = stopIndex {
			// We did not write all of the data, remove what was written.
            // 我们没有写出所有的数据，删除了写入的内容。
			if removeEnd > 0 {
				chain.removeSubrange(0..<removeEnd)
			}
		} else {
			// All of the data was written.
            // 所有数据都已写入。
			chain.removeAll(keepingCapacity: false)
		}

		return result
	}

	/// Remove all data from the list.
    /// 从列表中删除所有数据。
	func clear() {
		chain.removeAll(keepingCapacity: false)
	}
}

/// A object containing a sockaddr_in6 structure.
/// 包含sockaddr_in6结构的对象。
class SocketAddress6 {

	// MARK: - Properties

	/// The sockaddr_in6 structure.
    /// sockaddr_in6结构。
	var sin6: sockaddr_in6

	/// The IPv6 address as a string.
    /// 将IPv6地址作为字符串。
	var stringValue: String? {
    return withUnsafePointer(to: &sin6) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { saToString($0) } }
	}

	// MARK: - Initializers

	init() {
		sin6 = sockaddr_in6()
		sin6.sin6_len = __uint8_t(MemoryLayout<sockaddr_in6>.size)
		sin6.sin6_family = sa_family_t(AF_INET6)
		sin6.sin6_port = in_port_t(0)
		sin6.sin6_addr = in6addr_any
		sin6.sin6_scope_id = __uint32_t(0)
		sin6.sin6_flowinfo = __uint32_t(0)
	}

	convenience init(otherAddress: SocketAddress6) {
		self.init()
		sin6 = otherAddress.sin6
	}

	/// Set the IPv6 address from a string.
    /// 从字符串中设置IPv6地址。
	func setFromString(_ str: String) -> Bool {
		return str.withCString({ cs in inet_pton(AF_INET6, cs, &sin6.sin6_addr) }) == 1
	}

	/// Set the port.
    /// 设置端口。
	func setPort(_ port: Int) {
		sin6.sin6_port = in_port_t(UInt16(port).bigEndian)
	}
}

/// An object containing a sockaddr_in structure.
/// 包含sockaddr_in结构的对象。
class SocketAddress {

	// MARK: - Properties

	/// The sockaddr_in structure.
    /// sockaddr_in结构。
	var sin: sockaddr_in

	/// The IPv4 address in string form.
    /// 字符串形式的IPv4地址。
	var stringValue: String? {
    return withUnsafePointer(to: &sin) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { saToString($0) } }
	}

	// MARK: - Initializers

	init() {
		sin = sockaddr_in(sin_len:__uint8_t(MemoryLayout<sockaddr_in>.size), sin_family:sa_family_t(AF_INET), sin_port:in_port_t(0), sin_addr:in_addr(s_addr: 0), sin_zero:(Int8(0), Int8(0), Int8(0), Int8(0), Int8(0), Int8(0), Int8(0), Int8(0)))
	}

	convenience init(otherAddress: SocketAddress) {
		self.init()
		sin = otherAddress.sin
	}

	/// Set the IPv4 address from a string.
    /// 从字符串中设置IPv4地址。
	func setFromString(_ str: String) -> Bool {
		return str.withCString({ cs in inet_pton(AF_INET, cs, &sin.sin_addr) }) == 1
	}

	/// Set the port.
    /// 设置端口。
	func setPort(_ port: Int) {
		sin.sin_port = in_port_t(UInt16(port).bigEndian)
	}

	/// Increment the address by a given amount.
    /// 将地址增加一个给定的数量。
	func increment(_ amount: UInt32) {
		let networkAddress = sin.sin_addr.s_addr.byteSwapped + amount
		sin.sin_addr.s_addr = networkAddress.byteSwapped
	}

	/// Get the difference between this address and another address.
    /// 获取这个地址和另一个地址的区别。
	func difference(_ otherAddress: SocketAddress) -> Int64 {
		return Int64(sin.sin_addr.s_addr.byteSwapped - otherAddress.sin.sin_addr.s_addr.byteSwapped)
	}
}

// MARK: - Utility Functions

/// Convert a sockaddr structure to a string.
/// 将sockaddr结构转换为字符串。
func saToString(_ sa: UnsafePointer<sockaddr>) -> String? {
	var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
	var portBuffer = [CChar](repeating: 0, count: Int(NI_MAXSERV))

	guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &hostBuffer, socklen_t(hostBuffer.count), &portBuffer, socklen_t(portBuffer.count), NI_NUMERICHOST | NI_NUMERICSERV) == 0
		else { return nil }

	return String(cString: hostBuffer)
}

/// Write a blob of data to a stream starting from a particular offset.
/// 从一个特定的偏移量开始，将一个数据块写入流中。
func writeData(_ data: Data, toStream stream: OutputStream, startingAtOffset offset: Int) -> Int {
	var written = 0
	var currentOffset = offset
	while stream.hasSpaceAvailable && currentOffset < data.count {

		let writeResult = stream.write((data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count) + currentOffset, maxLength: data.count - currentOffset)
		guard writeResult >= 0 else { return writeResult }

		written += writeResult
		currentOffset += writeResult
	}
	
	return written
}

/// Create a SimpleTunnel protocol message dictionary.
/// 创建一个SimpleTunnel协议消息字典。
public func createMessagePropertiesForConnection(_ connectionIdentifier: Int, commandType: TunnelCommand, extraProperties: [String: AnyObject] = [:]) -> [String: AnyObject] {
	// Start out with the "extra properties" that the caller specified.
    // 从调用者指定的“额外属性”开始。
	var properties = extraProperties

	// Add in the standard properties common to all messages.
    // 添加所有消息通用的标准属性。
	properties[TunnelMessageKey.Identifier.rawValue] = connectionIdentifier as AnyObject?
	properties[TunnelMessageKey.Command.rawValue] = commandType.rawValue as AnyObject?
	
	return properties
}

/// Keys in the tunnel server configuration plist.
/// 隧道服务器配置plist中的密钥。
public enum SettingsKey: String {
	case IPv4 = "IPv4"
	case DNS = "DNS"
	case Proxies = "Proxies"
	case Pool = "Pool"
	case StartAddress = "StartAddress"
	case EndAddress = "EndAddress"
	case Servers = "Servers"
	case SearchDomains = "SearchDomains"
	case Address = "Address"
	case Netmask = "Netmask"
	case Routes = "Routes"
}

/// Get a value from a plist given a list of keys.
/// 从给出键列表的plist获取值。
public func getValueFromPlist(_ plist: [NSObject: AnyObject], keyArray: [SettingsKey]) -> AnyObject? {
	var subPlist = plist
	for (index, key) in keyArray.enumerated() {
		if index == keyArray.count - 1 {
			return subPlist[key.rawValue as NSString]
		}
		else if let subSubPlist = subPlist[key.rawValue as NSString] as? [NSObject: AnyObject] {
			subPlist = subSubPlist
		}
		else {
			break
		}
	}

	return nil
}

/// Create a new range by incrementing the start of the given range by a given ammount.
/// 通过给定的ammount递增给定范围的开始来创建一个新的范围。
func rangeByMovingStartOfRange(_ range: Range<Int>, byCount: Int) -> CountableRange<Int> {
	return (range.lowerBound + byCount)..<range.upperBound
}

public func simpleTunnelLog(_ message: String) {
	NSLog(message)
}
