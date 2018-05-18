/*
	Copyright (C) 2016 Apple Inc. All Rights Reserved.
	See LICENSE.txt for this sample’s licensing information
	
	Abstract:
	This file contains the ProxyAutoConfigScriptController class, which controls a view used to input the text of a Proxy Auto-Configuration Script.
    该文件包含ProxyAutoConfigScriptController类，该类控制用于输入代理自动配置脚本文本的视图。
*/

import UIKit
import NetworkExtension

/// A view controller object for a view that contains a text box where the user can enter a Proxy Auto-Configuration (PAC) script.
class ProxyAutoConfigScriptController: UIViewController {

	// MARK: Properties

	/// The text view containing the script.
	@IBOutlet weak var scriptText: UITextView!

	/// The block to call when the user taps on the "Done" button.
	var saveScriptCallback: (String?) -> Void = { script in return }

	// MARK: Interface

	/// Call the saveScriptCallback and transition back to the proxy settings view.
	@IBAction func saveScript(_ sender: AnyObject) {
		saveScriptCallback(scriptText.text)
		performSegue(withIdentifier: "save-proxy-script", sender: sender)
	}
}
