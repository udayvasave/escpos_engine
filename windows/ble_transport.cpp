#include "ble_transport.h"

#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <functional>
#include <future>
#include <map>
#include <mutex>
#include <optional>
#include <queue>
#include <thread>

namespace escpos_engine {

namespace {

using namespace winrt;
using namespace Windows::Devices::Bluetooth;
using namespace Windows::Devices::Bluetooth::Advertisement;
using namespace Windows::Devices::Bluetooth::GenericAttributeProfile;
using namespace Windows::Storage::Streams;

// Nordic UART Service — common on BLE thermal printers.
const guid kNusServiceUuid{0x6E400001, 0xB5A3, 0xF393,
                           {0xE0, 0xA9, 0x50, 0x0E, 0x24, 0xDC, 0xCA, 0x9E}};
const guid kNusTxUuid{0x6E400002, 0xB5A3, 0xF393,
                      {0xE0, 0xA9, 0x50, 0x0E, 0x24, 0xDC, 0xCA, 0x9E}};

// Alternate UUIDs seen on some Chinese BLE printers.
const guid kAltServiceUuid{0x0000FFF0, 0x0000, 0x1000,
                           {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};
const guid kAltWriteUuid{0x0000FFF1, 0x0000, 0x1000,
                         {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};

struct BleScanEntry {
  std::string address;
  std::string name;
  int rssi = 0;
};

std::mutex g_worker_mutex;
std::condition_variable g_worker_cv;
std::queue<std::function<void()>> g_worker_tasks;
std::thread g_worker_thread;
bool g_worker_running = false;

void EnsureBleWorkerThread() {
  static std::once_flag once;
  std::call_once(once, []() {
    g_worker_running = true;
    g_worker_thread = std::thread([]() {
      // Dedicated MTA thread — WinRT GATT APIs assert !is_sta_thread().
      // Flutter's main thread is STA (CoInitializeEx); never call WinRT there.
      init_apartment(apartment_type::multi_threaded);
      while (g_worker_running) {
        std::function<void()> task;
        {
          std::unique_lock<std::mutex> lock(g_worker_mutex);
          g_worker_cv.wait(lock, [] {
            return !g_worker_tasks.empty() || !g_worker_running;
          });
          if (!g_worker_running && g_worker_tasks.empty()) {
            break;
          }
          if (g_worker_tasks.empty()) {
            continue;
          }
          task = std::move(g_worker_tasks.front());
          g_worker_tasks.pop();
        }
        if (task) {
          task();
        }
      }
    });
  });
}

template <typename Result>
Result RunOnBleWorker(std::function<Result()> work, Result fallback) {
  EnsureBleWorkerThread();
  auto promise = std::make_shared<std::promise<Result>>();
  auto future = promise->get_future();
  {
    std::lock_guard<std::mutex> lock(g_worker_mutex);
    g_worker_tasks.push([promise, work = std::move(work), fallback]() {
      try {
        promise->set_value(work());
      } catch (...) {
        promise->set_value(fallback);
      }
    });
  }
  g_worker_cv.notify_one();
  return future.get();
}

std::string FormatBluetoothAddress(uint64_t address) {
  const uint8_t *bytes = reinterpret_cast<const uint8_t *>(&address);
  char buffer[18];
  std::snprintf(buffer, sizeof(buffer), "%02X:%02X:%02X:%02X:%02X:%02X",
                bytes[5], bytes[4], bytes[3], bytes[2], bytes[1], bytes[0]);
  return std::string(buffer);
}

int ParseHexByte(const char *text) {
  int value = 0;
  for (int i = 0; i < 2; ++i) {
    const char c = text[i];
    value <<= 4;
    if (c >= '0' && c <= '9') {
      value |= c - '0';
    } else if (c >= 'A' && c <= 'F') {
      value |= c - 'A' + 10;
    } else if (c >= 'a' && c <= 'f') {
      value |= c - 'a' + 10;
    } else {
      return -1;
    }
  }
  return value;
}

uint64_t ParseBluetoothAddress(const std::string &address) {
  if (address.size() != 17) {
    return 0;
  }
  uint64_t value = 0;
  for (int i = 0; i < 6; ++i) {
    const size_t offset = static_cast<size_t>(i * 3);
    const int byte = ParseHexByte(address.c_str() + offset);
    if (byte < 0) {
      return 0;
    }
    if (i < 5 && address[offset + 2] != ':') {
      return 0;
    }
    value = (value << 8) | static_cast<uint64_t>(byte);
  }
  return value;
}

std::optional<guid> ParseGuid(const std::string &uuid_text) {
  if (uuid_text.empty()) {
    return std::nullopt;
  }
  try {
    return guid{winrt::to_hstring(uuid_text)};
  } catch (...) {
    return std::nullopt;
  }
}

IBuffer MakeBuffer(const uint8_t *data, size_t length) {
  DataWriter writer;
  writer.WriteBytes(winrt::array_view<const uint8_t>(data, data + length));
  return writer.DetachBuffer();
}

bool CharacteristicIsWritable(GattCharacteristicProperties props) {
  return (props & GattCharacteristicProperties::Write) ==
             GattCharacteristicProperties::Write ||
         (props & GattCharacteristicProperties::WriteWithoutResponse) ==
             GattCharacteristicProperties::WriteWithoutResponse;
}

bool TryWriteChunk(GattCharacteristic characteristic,
                   const std::vector<uint8_t> &data, size_t offset,
                   size_t length) {
  const auto buffer = MakeBuffer(data.data() + offset, length);
  const auto props = characteristic.CharacteristicProperties();

  auto try_option = [&](GattWriteOption option) {
    return characteristic.WriteValueAsync(buffer, option).get() ==
           GattCommunicationStatus::Success;
  };

  if ((props & GattCharacteristicProperties::WriteWithoutResponse) ==
      GattCharacteristicProperties::WriteWithoutResponse) {
    if (try_option(GattWriteOption::WriteWithoutResponse)) {
      return true;
    }
  }
  if ((props & GattCharacteristicProperties::Write) ==
      GattCharacteristicProperties::Write) {
    if (try_option(GattWriteOption::WriteWithResponse)) {
      return true;
    }
  }
  return false;
}

bool IsClientConfigUuid(const guid &uuid) {
  // Skip CCCD — writable but not for print data.
  const guid kCccd{0x00002902, 0x0000, 0x1000,
                   {0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB}};
  return uuid == kCccd;
}

size_t EffectiveChunkSize(const GattCharacteristic &characteristic) {
  (void)characteristic;
  // Default ATT MTU payload (23 - 3 overhead). Safe for all BLE printers.
  return 20;
}

std::optional<GattCharacteristic> FindWriteCharacteristic(
    BluetoothLEDevice device, const std::optional<guid> &service_filter,
    const std::optional<guid> &characteristic_filter) {
  const auto services_result =
      device.GetGattServicesAsync(BluetoothCacheMode::Uncached).get();
  if (services_result.Status() != GattCommunicationStatus::Success) {
    return std::nullopt;
  }

  auto try_match = [&](const guid &service_uuid,
                       const guid &char_uuid) -> std::optional<GattCharacteristic> {
    const auto services = services_result.Services();
    for (uint32_t i = 0; i < services.Size(); ++i) {
      const auto service = services.GetAt(i);
      if (service.Uuid() != service_uuid) {
        continue;
      }
      const auto chars =
          service.GetCharacteristicsAsync(BluetoothCacheMode::Uncached).get();
      if (chars.Status() != GattCommunicationStatus::Success) {
        continue;
      }
      const auto characteristics = chars.Characteristics();
      for (uint32_t j = 0; j < characteristics.Size(); ++j) {
        const auto characteristic = characteristics.GetAt(j);
        if (characteristic.Uuid() == char_uuid &&
            CharacteristicIsWritable(characteristic.CharacteristicProperties())) {
          return characteristic;
        }
      }
    }
    return std::nullopt;
  };

  if (service_filter && characteristic_filter) {
    if (auto found = try_match(*service_filter, *characteristic_filter)) {
      return found;
    }
  }

  if (auto found = try_match(kNusServiceUuid, kNusTxUuid)) {
    return found;
  }
  if (auto found = try_match(kAltServiceUuid, kAltWriteUuid)) {
    return found;
  }

  const auto all_services = services_result.Services();
  for (uint32_t i = 0; i < all_services.Size(); ++i) {
    const auto service = all_services.GetAt(i);
    const auto chars =
        service.GetCharacteristicsAsync(BluetoothCacheMode::Uncached).get();
    if (chars.Status() != GattCommunicationStatus::Success) {
      continue;
    }
    const auto characteristics = chars.Characteristics();
    for (uint32_t j = 0; j < characteristics.Size(); ++j) {
      const auto characteristic = characteristics.GetAt(j);
      if (IsClientConfigUuid(characteristic.Uuid())) {
        continue;
      }
      if (CharacteristicIsWritable(characteristic.CharacteristicProperties())) {
        return characteristic;
      }
    }
  }

  return std::nullopt;
}

flutter::EncodableList ScanBleDevicesImpl(int timeout_ms) {
  std::map<uint64_t, BleScanEntry> found;
  std::mutex mutex;

  BluetoothLEAdvertisementWatcher watcher;
  watcher.ScanningMode(BluetoothLEScanningMode::Active);

  auto token = watcher.Received([&](const auto &,
                                    BluetoothLEAdvertisementReceivedEventArgs args) {
    const uint64_t address = args.BluetoothAddress();
    if (address == 0) {
      return;
    }

    std::lock_guard<std::mutex> lock(mutex);
    auto &entry = found[address];
    entry.address = FormatBluetoothAddress(address);
    entry.rssi = args.RawSignalStrengthInDBm();

    const auto local_name = args.Advertisement().LocalName();
    if (!local_name.empty()) {
      entry.name = winrt::to_string(local_name);
    } else if (entry.name.empty()) {
      entry.name = entry.address;
    }
  });

  watcher.Start();
  std::this_thread::sleep_for(std::chrono::milliseconds(timeout_ms));
  watcher.Stop();
  watcher.Received(token);

  flutter::EncodableList devices;
  for (const auto &pair : found) {
    flutter::EncodableMap device;
    device[flutter::EncodableValue("address")] =
        flutter::EncodableValue(pair.second.address);
    device[flutter::EncodableValue("name")] =
        flutter::EncodableValue(pair.second.name);
    device[flutter::EncodableValue("rssi")] =
        flutter::EncodableValue(pair.second.rssi);
    devices.push_back(flutter::EncodableValue(device));
  }
  return devices;
}

bool WriteBleBytesImpl(const std::string &address,
                       const std::vector<uint8_t> &data,
                       const std::string &service_uuid,
                       const std::string &characteristic_uuid) {
  if (address.empty() || data.empty()) {
    return false;
  }

  const uint64_t bt_address = ParseBluetoothAddress(address);
  if (bt_address == 0) {
    return false;
  }

  auto device = BluetoothLEDevice::FromBluetoothAddressAsync(bt_address).get();
  if (!device) {
    return false;
  }

  auto session = GattSession::FromDeviceIdAsync(device.BluetoothDeviceId()).get();
  if (session) {
    session.MaintainConnection(true);
  }

  const auto service_filter = ParseGuid(service_uuid);
  const auto characteristic_filter = ParseGuid(characteristic_uuid);
  const auto write_char =
      FindWriteCharacteristic(device, service_filter, characteristic_filter);
  if (!write_char) {
    device.Close();
    return false;
  }

  const size_t chunk_size = EffectiveChunkSize(*write_char);
  for (size_t offset = 0; offset < data.size(); offset += chunk_size) {
    const size_t length = (std::min)(chunk_size, data.size() - offset);
    if (!TryWriteChunk(*write_char, data, offset, length)) {
      device.Close();
      return false;
    }
    if (offset + length < data.size()) {
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
  }

  device.Close();
  return true;
}

bool IsBleDeviceReachableImpl(const std::string &address) {
  const uint64_t bt_address = ParseBluetoothAddress(address);
  if (bt_address == 0) {
    return false;
  }

  auto device = BluetoothLEDevice::FromBluetoothAddressAsync(bt_address).get();
  if (!device) {
    return false;
  }
  const auto services =
      device.GetGattServicesAsync(BluetoothCacheMode::Cached).get();
  device.Close();
  return services.Status() == GattCommunicationStatus::Success;
}

}  // namespace

void EnsureBleInitialized() {
  EnsureBleWorkerThread();
}

flutter::EncodableList ScanBleDevices(int timeout_ms) {
  if (timeout_ms < 1000) {
    timeout_ms = 1000;
  }
  if (timeout_ms > 30000) {
    timeout_ms = 30000;
  }

  const int scan_ms = timeout_ms;
  return RunOnBleWorker<flutter::EncodableList>(
      [scan_ms]() { return ScanBleDevicesImpl(scan_ms); },
      flutter::EncodableList{});
}

bool WriteBleBytes(const std::string &address,
                   const std::vector<uint8_t> &data,
                   const std::string &service_uuid,
                   const std::string &characteristic_uuid) {
  return RunOnBleWorker<bool>(
      [=]() {
        return WriteBleBytesImpl(address, data, service_uuid, characteristic_uuid);
      },
      false);
}

bool IsBleDeviceReachable(const std::string &address) {
  return RunOnBleWorker<bool>(
      [address]() { return IsBleDeviceReachableImpl(address); }, false);
}

}  // namespace escpos_engine
