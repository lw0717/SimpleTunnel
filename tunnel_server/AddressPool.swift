/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	This file contains the AddressPool class. The AddressPool class is used to manage a pool of IP addresses.
    该文件包含AddressPool类。 AddressPool类用于管理IP地址池。
*/

import Foundation

/// An object that contains a pool of IP addresses to assign to tunnel clients.
/// 包含要分配给隧道客户端的IP地址池的对象。
class AddressPool {

	// MARK: - Properties

	/// The start address of the pool.
    /// 池的起始地址。
	let baseAddress: SocketAddress

	/// The number of addresses in the pool.
    /// 池中的地址数量。
	var size: UInt64 = 0

	/// A list of flags indicating which addresses in the pool are currently allocated to clients.
    /// 指示池中哪些地址当前分配给客户端的标志列表。
	var inUseMask: [Bool]

	/// A dispatch queue for serializing access to the pool.
    /// 用于序列化对池的访问的分派队列。
	let queue: DispatchQueue

	// MARK: - Initializers
	
	init(startAddress: String, endAddress: String) {
		baseAddress = SocketAddress()
		inUseMask = [Bool](repeating: false, count: 0)
		queue = DispatchQueue(label: "AddressPoolQueue")

		let start = SocketAddress()
		let end = SocketAddress()

		// Verify that the address pool is specified correctly.
        // 验证地址池是否正确指定。

		guard start.setFromString(startAddress) &&
			end.setFromString(endAddress) &&
			start.sin.sin_family == end.sin.sin_family
			else { return }

		guard start.sin.sin_family == sa_family_t(AF_INET) else {
			simpleTunnelLog("IPv6 is not currently supported")
			return
		}
		guard (start.sin.sin_addr.s_addr & 0xffff) == (end.sin.sin_addr.s_addr & 0xffff) else {
			simpleTunnelLog("start address (\(startAddress)) is not in the same class B network as end address (\(endAddress)) ")
			return
		}

		let difference = end.difference(start)
		guard difference >= 0 else {
			simpleTunnelLog("start address (\(startAddress)) is greater than end address (\(endAddress))")
			return
		}

		baseAddress.sin = start.sin
		size = UInt64(difference)
		inUseMask = [Bool](repeating: false, count: Int(size))
	}

	/// Allocate an address from the pool.
    /// 分配池中的地址。
	func allocateAddress() -> String? {
		var result: String?

		queue.sync() {
			let address = SocketAddress(otherAddress: self.baseAddress)

			// Look for an address that is not currently allocated
			for (index, inUse) in self.inUseMask.enumerated() {
				if !inUse {
					address.increment(UInt32(index))
					self.inUseMask[index] = true
					result = address.stringValue
					break
				}
			}
		}

		simpleTunnelLog("Allocated address \(result)")
		return result
	}

	/// Deallocate an address in the pool.
    /// 取消分配池中的地址。
	func deallocateAddress(addrString: String) {
		queue.sync() {
			let address = SocketAddress()

			guard address.setFromString(addrString) else { return }

			let difference = address.difference(self.baseAddress)
			if difference >= 0 && difference < Int64(self.inUseMask.count) {
				self.inUseMask[Int(difference)] = false
			}
		}
	}
}
