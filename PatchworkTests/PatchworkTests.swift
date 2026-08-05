import Testing
@testable import Patchwork

struct PatchworkTests {
    @Test func validatesSubductionEndpointURLs() {
        #expect(AppModel.isValidSubductionEndpoint("wss://subduction.sync.inkandswitch.com"))
        #expect(AppModel.isValidSubductionEndpoint("ws://127.0.0.1:43217"))
        #expect(!AppModel.isValidSubductionEndpoint("https://subduction.sync.inkandswitch.com"))
        #expect(!AppModel.isValidSubductionEndpoint("ws://"))
        #expect(!AppModel.isValidSubductionEndpoint(""))
    }
}
