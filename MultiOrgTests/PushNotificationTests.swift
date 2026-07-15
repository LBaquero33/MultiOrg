import Foundation
import Testing
import UserNotifications
@testable import MultiOrg

@Suite("APNs push notification client")
struct PushNotificationTests {
  private let userA = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
  private let userB = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

  @Test("Device token converts to canonical lowercase hexadecimal")
  func tokenHex() {
    #expect(Data([0x00, 0x0f, 0xa1, 0xff]).apnsTokenHex == "000fa1ff")
  }

  @Test("Build environment maps development and production without guessing")
  func environmentMapping() {
    #expect(PushEnvironment.fromBuildValue("development") == .sandbox)
    #expect(PushEnvironment.fromBuildValue("sandbox") == .sandbox)
    #expect(PushEnvironment.fromBuildValue("production") == .production)
    #expect(PushEnvironment.fromBuildValue("unexpected") == nil)
  }

  @Test("Registration request contains device facts but no user identity")
  func requestExcludesActor() throws {
    let request = PushDeviceRegisterRequest(
      device_token: "ab", platform: .ios, environment: .sandbox,
      app_bundle_id: "com.multiorg.app", app_version: "1", os_version: "test",
      notifications_authorized: true
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
    )
    #expect(object["user_id"] == nil)
    #expect(object["actor_id"] == nil)
    #expect(object["recipient_user_id"] == nil)
    #expect(object["device_token"] as? String == "ab")
  }

  @Test("Permission and APNs token register after sign-in")
  @MainActor
  func permissionAndRegistration() async {
    let fixture = makeFixture(status: .authorized)
    await fixture.manager.configure(actorId: userA, service: fixture.service)
    #expect(fixture.system.remoteRegistrationCalls == 1)
    await fixture.manager.receiveDeviceToken(Data(repeating: 0xab, count: 32))
    #expect(fixture.service.registerRequests.count == 1)
    #expect(fixture.service.registerRequests.first?.device_token == String(repeating: "ab", count: 32))
    #expect(fixture.manager.registrationState == .registered)
  }

  @Test("Not-determined permission requests authorization then APNs registration")
  @MainActor
  func permissionRequest() async {
    let fixture = makeFixture(status: .notDetermined)
    fixture.system.statusAfterRequest = .authorized
    await fixture.manager.configure(actorId: userA, service: fixture.service)
    await fixture.manager.requestPermission()
    #expect(fixture.system.permissionRequestCalls == 1)
    #expect(fixture.system.remoteRegistrationCalls == 1)
  }

  @Test("Account switch re-registers the stable token and sign-out detaches it")
  @MainActor
  func accountSwitchAndSignOut() async {
    let fixture = makeFixture(status: .authorized)
    await fixture.manager.configure(actorId: userA, service: fixture.service)
    await fixture.manager.receiveDeviceToken(Data(repeating: 0xcd, count: 32))
    await fixture.manager.configure(actorId: userB, service: fixture.service)
    #expect(fixture.service.registerRequests.count == 2)
    await fixture.manager.detachBeforeSignOut()
    #expect(fixture.service.unregisterRequests.count == 1)
    #expect(fixture.service.unregisterRequests.first?.device_token == String(repeating: "cd", count: 32))
  }

  @Test("Denied notification settings opens the system settings action")
  @MainActor
  func settingsAction() async {
    let fixture = makeFixture(status: .denied)
    await fixture.manager.configure(actorId: userA, service: fixture.service)
    fixture.manager.openSystemSettings()
    #expect(fixture.system.openSettingsCalls == 1)
    #expect(fixture.system.remoteRegistrationCalls == 0)
  }

  @Test("Remote payload accepts only the versioned opaque notification ID")
  func remotePayload() throws {
    let notificationId = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    let valid: [AnyHashable: Any] = [
      "home_plate": [
        "schema_version": "notification_v1",
        "notification_id": notificationId.uuidString,
        "action_route": "payment_request",
      ],
    ]
    #expect(RemoteNotificationReference(userInfo: valid)?.notificationId == notificationId)
    #expect(RemoteNotificationReference(userInfo: ["home_plate": ["notification_id": notificationId.uuidString]]) == nil)
    #expect(RemoteNotificationReference(userInfo: ["home_plate": ["schema_version": "notification_v1", "notification_id": "bad"]]) == nil)
  }

  @MainActor
  private func makeFixture(status: UNAuthorizationStatus) -> (
    manager: PushNotificationManager,
    system: MockPushSystem,
    service: MockPushService
  ) {
    let suite = "PushNotificationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let system = MockPushSystem(status: status)
    let service = MockPushService()
    let manager = PushNotificationManager(
      system: system,
      defaults: defaults,
      registrationFacts: { (.sandbox, "com.multiorg.app", .ios) }
    )
    return (manager, system, service)
  }
}

@MainActor
private final class MockPushSystem: PushNotificationSystem {
  var status: UNAuthorizationStatus
  var statusAfterRequest: UNAuthorizationStatus?
  var permissionRequestCalls = 0
  var remoteRegistrationCalls = 0
  var openSettingsCalls = 0

  init(status: UNAuthorizationStatus) { self.status = status }
  func authorizationStatus() async -> UNAuthorizationStatus { status }
  func requestAuthorization() async throws -> Bool {
    permissionRequestCalls += 1
    if let statusAfterRequest { status = statusAfterRequest }
    return status == .authorized
  }
  func registerForRemoteNotifications() { remoteRegistrationCalls += 1 }
  func openSystemSettings() { openSettingsCalls += 1 }
}

@MainActor
private final class MockPushService: PushDeviceRegistrationServicing {
  var registerRequests: [PushDeviceRegisterRequest] = []
  var unregisterRequests: [PushDeviceUnregisterRequest] = []

  func registerPushDevice(_ request: PushDeviceRegisterRequest) async throws -> PushDevice {
    registerRequests.append(request)
    return PushDevice(
      id: UUID(), platform: request.platform, environment: request.environment,
      appBundleId: request.app_bundle_id, notificationsAuthorized: true,
      lastRegisteredAt: "2026-07-15T12:00:00Z", disabledAt: nil
    )
  }

  func unregisterPushDevice(_ request: PushDeviceUnregisterRequest) async throws {
    unregisterRequests.append(request)
  }
}
