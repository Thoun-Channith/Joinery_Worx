import UIKit
import Flutter
import GoogleMaps

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("AIzaSyAWZnKppxh-gJRcBPgDGHfbcQfrXZC_eRg")
    GeneratedPluginRegistrant.register(with: self)

    // REMOVE the BackgroundFetch.registerBGProcessingTask code
    // The background_fetch plugin handles this automatically

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}