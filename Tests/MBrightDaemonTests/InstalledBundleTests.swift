import Testing
@testable import MBrightCore
@testable import MBrightDaemon

@Test func bundleIsDerivedFromTheHelpersPath() {
    let bundle = InstalledBundle(daemonExecutable: "/Users/me/Applications/mbright.app/Contents/Helpers/mbrightd")
    #expect(bundle?.root.path == "/Users/me/Applications/mbright.app")
    #expect(bundle?.daemon == "/Users/me/Applications/mbright.app/Contents/Helpers/mbrightd")
    #expect(bundle?.app == "/Users/me/Applications/mbright.app/Contents/MacOS/mbright-menubar")
    #expect(bundle?.program(for: Config(login: true, ui: true)) == bundle?.app)
    #expect(bundle?.program(for: Config(login: true, ui: false)) == bundle?.daemon)
}

@Test func anythingOutsideABundleIsNotInstalled() {
    #expect(InstalledBundle(daemonExecutable: "/Users/me/.cache/mbright/build/debug/mbrightd") == nil)
    #expect(InstalledBundle(daemonExecutable: "/Users/me/Applications/mbright.app/Contents/MacOS/mbrightd") == nil)
    #expect(InstalledBundle(daemonExecutable: "/Users/me/Applications/mbright.app/Contents/Helpers/other") == nil)
    #expect(InstalledBundle(daemonExecutable: "/opt/mbright/Contents/Helpers/mbrightd") == nil)
}
