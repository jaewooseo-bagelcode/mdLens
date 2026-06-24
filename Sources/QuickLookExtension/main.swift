import Foundation

// App extensions enter through NSExtensionMain (provided by the system at load
// time), not the normal main. This lets a SwiftPM executable target act as an .appex.
@_silgen_name("NSExtensionMain")
func NSExtensionMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

exit(NSExtensionMain(CommandLine.argc, CommandLine.unsafeArgv))
