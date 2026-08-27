import QtQuick
import QtTest

import "../../../shell/services"

TestCase {
  id: testCase
  name: "FabricClientDormantIntegration"

  FabricClient {
    id: client
    active: false
    allowedMethods: []
  }

  SignalSpy {
    id: rejectedSpy
    target: client
    signalName: "requestRejected"
  }

  function init() {
    rejectedSpy.clear()
  }

  function test_dormantClientLoadsWithoutAuthority() {
    compare(client.connectionState, "disabled")
    compare(client.ready, false)
    compare(client.pendingRequestCount, 0)
    compare(client.bufferedEventCount, 0)
    compare(client.request("health", {}), "")
    compare(rejectedSpy.count, 1)
    compare(rejectedSpy.signalArguments[0][0].code, "client.method-denied")
  }
}
