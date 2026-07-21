#ifndef ESCPOS_ENGINE_BLE_TRANSPORT_H_
#define ESCPOS_ENGINE_BLE_TRANSPORT_H_

#include <flutter/encodable_value.h>

#include <cstdint>
#include <string>
#include <vector>

namespace escpos_engine {

/// Initializes WinRT for BLE (safe to call multiple times).
void EnsureBleInitialized();

/// Scans for BLE devices for [timeout_ms] milliseconds.
flutter::EncodableList ScanBleDevices(int timeout_ms);

/// Writes [data] to a BLE printer at [address] (MAC like `AA:BB:CC:DD:EE:FF`).
/// Optional [service_uuid] / [characteristic_uuid] override auto-discovery.
bool WriteBleBytes(const std::string &address,
                   const std::vector<uint8_t> &data,
                   const std::string &service_uuid,
                   const std::string &characteristic_uuid);

/// Returns whether a BLE device at [address] accepts a GATT connection.
bool IsBleDeviceReachable(const std::string &address);

}  // namespace escpos_engine

#endif  // ESCPOS_ENGINE_BLE_TRANSPORT_H_
