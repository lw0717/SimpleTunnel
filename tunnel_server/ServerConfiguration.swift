/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	This file contains the ServerConfiguration class. The ServerConfiguration class is used to parse the SimpleTunnel server configuration.
    该文件包含ServerConfiguration类。 ServerConfiguration类用于解析SimpleTunnel服务器配置。
*/

import Foundation
import SystemConfiguration

/// An object containing configuration settings for the SimpleTunnel server.
/// 包含SimpleTunnel服务器配置设置的对象。
class ServerConfiguration {

	// MARK: - Properties

	/// A dictionary containing configuration parameters.
    /// 包含配置参数的字典。
	var configuration: [String: Any]

	/// A pool of IP addresses to allocate to clients.
    /// 分配给客户端的IP地址池。
	var addressPool: AddressPool?

	// MARK: - Initializers

	init() {
		configuration = [String: Any]()
		addressPool = nil
	}

	// MARK: - Interface

	/// Read the configuration settings from a plist on disk.
    /// 从磁盘上的plist读取配置设置。
	func loadFromFileAtPath(path: String) -> Bool {

		guard let fileStream = InputStream(fileAtPath: path) else {
			simpleTunnelLog("Failed to open \(path) for reading")
			return false
		}

		fileStream.open()

		var newConfiguration: [String: Any]
		do {
			 newConfiguration = try PropertyListSerialization.propertyList(with: fileStream, options: .mutableContainers, format: nil) as! [String: Any]
		}
		catch {
			simpleTunnelLog("Failed to read the configuration from \(path): \(error)")
			return false
		}

		guard let startAddress = getValueFromPlist(newConfiguration as [NSObject : AnyObject], keyArray: [.IPv4, .Pool, .StartAddress]) as? String else {
			simpleTunnelLog("Missing v4 start address")
			return false
		}
		guard let endAddress = getValueFromPlist(newConfiguration as [NSObject : AnyObject], keyArray: [.IPv4, .Pool, .EndAddress]) as? String else {
			simpleTunnelLog("Missing v4 end address")
			return false
		}

		addressPool = AddressPool(startAddress: startAddress, endAddress: endAddress)

		// The configuration dictionary gets sent to clients as the tunnel settings dictionary. Remove the IP pool parameters.
        // 配置字典作为隧道设置字典发送给客户端。 删除IP池参数。
		if let value = newConfiguration[SettingsKey.IPv4.rawValue] as? [NSObject: Any] {
            var IPv4Dictionary = value
            
			IPv4Dictionary.removeValue(forKey: SettingsKey.Pool.rawValue as NSObject)
			newConfiguration[SettingsKey.IPv4.rawValue] = IPv4Dictionary as Any?
		}

		if !newConfiguration.keys.contains(where: { $0 == SettingsKey.DNS.rawValue }) {
			// The configuration does not specify any DNS configuration, so get the current system default resolver.
            // 配置没有指定任何DNS配置，因此获取当前系统默认解析器。
			let (DNSServers, DNSSearchDomains) = ServerConfiguration.copyDNSConfigurationFromSystem()

			newConfiguration[SettingsKey.DNS.rawValue] = [
				SettingsKey.Servers.rawValue: DNSServers,
				SettingsKey.SearchDomains.rawValue: DNSSearchDomains
			]
		}

		configuration = newConfiguration

		return true
	}

	/// Copy the default resolver configuration from the system on which the server is running.
    /// 从运行服务器的系统中复制默认的解析器配置。
	class func copyDNSConfigurationFromSystem() -> ([String], [String]) {
		let globalDNSKey = SCDynamicStoreKeyCreateNetworkGlobalEntity(kCFAllocatorDefault, kSCDynamicStoreDomainState, kSCEntNetDNS)
		var DNSServers = [String]()
		var DNSSearchDomains = [String]()

		// The default resolver configuration can be obtained from State:/Network/Global/DNS in the dynamic store.
        // 默认的解析器配置可以从动态存储中的State：/ Network / Global / DNS中获得。

		if let globalDNS = SCDynamicStoreCopyValue(nil, globalDNSKey) as? [NSObject: AnyObject],
			let servers = globalDNS[kSCPropNetDNSServerAddresses as NSString] as? [String]
		{
			if let searchDomains = globalDNS[kSCPropNetDNSSearchDomains as NSString] as? [String] {
				DNSSearchDomains = searchDomains
			}
			DNSServers = servers
		}

		return (DNSServers, DNSSearchDomains)
	}
}
