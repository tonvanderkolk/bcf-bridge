// Zet de typenaam (model) van de BCF2000 in CoreMIDI. Terugzetten: swift scripts/set-bcf-model.swift BCF2000
import CoreMIDI
var client = MIDIClientRef(); MIDIClientCreate("modelset" as CFString, nil, nil, &client)
func s(_ o: MIDIObjectRef, _ k: CFString) -> String { var u: Unmanaged<CFString>?; MIDIObjectGetStringProperty(o, k, &u); return (u?.takeRetainedValue() as String?) ?? "-" }
let newModel = CommandLine.arguments[1]
for i in 0..<MIDIGetNumberOfDevices() {
  let d = MIDIGetDevice(i)
  if s(d,kMIDIPropertyManufacturer) == "BEHRINGER" && s(d,kMIDIPropertyModel).hasPrefix("BCF2000") {
    print("voor: name=\(s(d,kMIDIPropertyName)) model=\(s(d,kMIDIPropertyModel))")
    let r = MIDIObjectSetStringProperty(d, kMIDIPropertyModel, newModel as CFString)
    print("status \(r)")
    print("na: model=\(s(d,kMIDIPropertyModel))")
  }
}
