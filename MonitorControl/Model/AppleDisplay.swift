//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Foundation
import os.log

class AppleDisplay: Display {
  private var displayQueue: DispatchQueue

  override init(_ identifier: CGDirectDisplayID, name: String, vendorNumber: UInt32?, modelNumber: UInt32?, serialNumber: UInt32?, isVirtual: Bool = false, isDummy: Bool = false) {
    self.displayQueue = DispatchQueue(label: String("displayQueue-\(identifier)"))
    super.init(identifier, name: name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber, isVirtual: isVirtual, isDummy: isDummy)
  }

  func updateApplePwmValue(brightness: Float) {
    // hard coded URL 
    let host = "http://imacpwm.local/light/internaldisplay/turn_on?brightness="
  
    let new_brightness = String(describing: brightness*255)
    let url = URL(string: host+new_brightness)
    os_log("Pushing slider and reporting delta for Apple display %{public}@", type: .info, String(describing: url))
    let task = URLSession.shared.dataTask(with: url! as URL) { data, response, error in
      guard let data = data, error == nil else { return }
      print(NSString(data: data, encoding: String.Encoding.utf8.rawValue) ?? "")
      }
      task.resume()
  }

  public func getAppleBrightness() -> Float {
    guard !self.isDummy else {
      return 1
    }
    var brightness: Float = 0
    DisplayServicesGetBrightness(self.identifier, &brightness)
    // Could we blindly assume the brightness stored in the ESP32 and the NVRAM variable is the same?
    return brightness
  }

  public func setAppleBrightness(value: Float) {
    guard !self.isDummy else {
      return
    }
    _ = self.displayQueue.sync {
      DisplayServicesSetBrightness(self.identifier, value)
      // REST API call to set the brightness via ESP32 
      updateApplePwmValue(brightness: value)
    }
  }

  override func setDirectBrightness(_ to: Float, transient: Bool = false) -> Bool {
    guard !self.isDummy else {
      return false
    }
    let value = max(min(to, 1), 0)
    self.setAppleBrightness(value: value)
    if !transient {
      self.savePref(value, for: .brightness)
      self.brightnessSyncSourceValue = value
      self.smoothBrightnessTransient = value
    }
    return true
  }

  override func getBrightness() -> Float {
    guard !self.isDummy else {
      return 1
    }
    if self.prefExists(for: .brightness) {
      return self.readPrefAsFloat(for: .brightness)
    } else {
      return self.getAppleBrightness()
    }
  }

  override func refreshBrightness() -> Float {
    guard !self.smoothBrightnessRunning else {
      return 0
    }
    let brightness = self.getAppleBrightness()
    let oldValue = self.brightnessSyncSourceValue
    self.savePref(brightness, for: .brightness)
    if brightness != oldValue {
      os_log("Pushing slider and reporting delta for Apple display %{public}@", type: .info, String(self.identifier))
      var newValue: Float

      if abs(brightness - oldValue) < 0.01 {
        newValue = brightness
      } else if brightness > oldValue {
        newValue = oldValue + max((brightness - oldValue) / 3, 0.005)
      } else {
        newValue = oldValue + min((brightness - oldValue) / 3, -0.005)
      }
      self.brightnessSyncSourceValue = newValue
      if let sliderHandler = self.sliderHandler[.brightness] {
        sliderHandler.setValue(newValue, displayID: self.identifier)
      }
      // update ESP32, too - obviously the Apple key settings are only reflected into the
      // app slider settings assuming the brightness will be controlled via Apple hardware
      updateApplePwmValue(brightness: newValue)
      return newValue - oldValue
    }
    return 0
  }
}
