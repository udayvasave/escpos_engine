#include "escpos_engine_plugin.h"

#include <windows.h>
#include <winspool.h>

#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

namespace escpos_engine {

namespace {

std::wstring Utf8ToWide(const std::string &utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int size_needed =
      MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (size_needed <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(size_needed - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, wide.data(), size_needed);
  return wide;
}

std::string WideToUtf8(const wchar_t *wide) {
  if (wide == nullptr || wide[0] == L'\0') {
    return std::string();
  }
  const int size_needed =
      WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  if (size_needed <= 0) {
    return std::string();
  }
  std::string utf8(static_cast<size_t>(size_needed - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide, -1, utf8.data(), size_needed, nullptr,
                      nullptr);
  return utf8;
}

std::string FormatWindowsError(const char *action) {
  const DWORD code = GetLastError();
  std::ostringstream stream;
  stream << action << " failed (Win32 error " << code << ")";
  return stream.str();
}

flutter::EncodableList ListPrinterNames() {
  flutter::EncodableList printers;

  DWORD needed = 0;
  DWORD returned = 0;
  EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, nullptr, 2,
                nullptr, 0, &needed, &returned);

  if (needed == 0) {
    return printers;
  }

  std::vector<BYTE> buffer(needed);
  if (!EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, nullptr, 2,
                     buffer.data(), needed, &needed, &returned)) {
    return printers;
  }

  auto *info = reinterpret_cast<PRINTER_INFO_2W *>(buffer.data());
  for (DWORD i = 0; i < returned; ++i) {
    if (info[i].pPrinterName != nullptr) {
      printers.push_back(
          flutter::EncodableValue(WideToUtf8(info[i].pPrinterName)));
    }
  }
  return printers;
}

bool IsPrinterReady(const std::wstring &printer_name) {
  if (printer_name.empty()) {
    return false;
  }

  HANDLE printer = nullptr;
  if (!OpenPrinterW(const_cast<LPWSTR>(printer_name.c_str()), &printer,
                    nullptr)) {
    return false;
  }

  DWORD needed = 0;
  GetPrinterW(printer, 2, nullptr, 0, &needed);
  if (needed == 0) {
    ClosePrinter(printer);
    return false;
  }

  std::vector<BYTE> buffer(needed);
  if (!GetPrinterW(printer, 2, buffer.data(), needed, &needed)) {
    ClosePrinter(printer);
    return false;
  }
  ClosePrinter(printer);

  const auto *info = reinterpret_cast<const PRINTER_INFO_2W *>(buffer.data());
  constexpr DWORD kBadStatus =
      PRINTER_STATUS_OFFLINE | PRINTER_STATUS_ERROR |
      PRINTER_STATUS_PAPER_OUT | PRINTER_STATUS_PAPER_JAM |
      PRINTER_STATUS_NO_TONER;
  if (info->Status & kBadStatus) {
    return false;
  }
  if (info->Attributes & PRINTER_ATTRIBUTE_WORK_OFFLINE) {
    return false;
  }
  return true;
}

bool PrintRawBytes(const std::wstring &printer_name,
                   const std::vector<uint8_t> &data) {
  HANDLE printer = nullptr;
  if (!OpenPrinterW(const_cast<LPWSTR>(printer_name.c_str()), &printer,
                    nullptr)) {
    return false;
  }

  DOC_INFO_1W doc_info = {};
  doc_info.pDocName = const_cast<LPWSTR>(L"ESC/POS RAW Job");
  doc_info.pOutputFile = nullptr;
  doc_info.pDatatype = const_cast<LPWSTR>(L"RAW");

  if (StartDocPrinterW(printer, 1, reinterpret_cast<LPBYTE>(&doc_info)) == 0) {
    ClosePrinter(printer);
    return false;
  }

  if (!StartPagePrinter(printer)) {
    EndDocPrinter(printer);
    ClosePrinter(printer);
    return false;
  }

  DWORD written = 0;
  const BOOL write_ok =
      WritePrinter(printer, const_cast<uint8_t *>(data.data()),
                   static_cast<DWORD>(data.size()), &written);

  EndPagePrinter(printer);
  EndDocPrinter(printer);
  ClosePrinter(printer);

  return write_ok == TRUE && written == data.size();
}

flutter::EncodableList ListSerialPorts() {
  flutter::EncodableList ports;
  for (int i = 1; i <= 256; ++i) {
    wchar_t name[16];
    swprintf_s(name, L"COM%d", i);
    COMMCONFIG config = {};
    DWORD size = sizeof(config);
    if (GetDefaultCommConfigW(name, &config, &size)) {
      ports.push_back(flutter::EncodableValue(WideToUtf8(name)));
    }
  }
  return ports;
}

std::wstring SerialDevicePath(const std::wstring &port_name) {
  // COM10+ requires \\.\COMx prefix.
  if (port_name.rfind(L"\\\\.\\", 0) == 0) {
    return port_name;
  }
  return L"\\\\.\\" + port_name;
}

bool WriteSerialBytes(const std::wstring &port_name,
                      const std::vector<uint8_t> &data, DWORD baud_rate) {
  const std::wstring path = SerialDevicePath(port_name);
  HANDLE handle =
      CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                  OPEN_EXISTING, 0, nullptr);
  if (handle == INVALID_HANDLE_VALUE) {
    return false;
  }

  DCB dcb = {};
  dcb.DCBlength = sizeof(DCB);
  if (!GetCommState(handle, &dcb)) {
    CloseHandle(handle);
    return false;
  }
  dcb.BaudRate = baud_rate;
  dcb.ByteSize = 8;
  dcb.Parity = NOPARITY;
  dcb.StopBits = ONESTOPBIT;
  dcb.fBinary = TRUE;
  dcb.fDtrControl = DTR_CONTROL_ENABLE;
  dcb.fRtsControl = RTS_CONTROL_ENABLE;
  if (!SetCommState(handle, &dcb)) {
    CloseHandle(handle);
    return false;
  }

  COMMTIMEOUTS timeouts = {};
  timeouts.WriteTotalTimeoutConstant = 5000;
  timeouts.WriteTotalTimeoutMultiplier = 10;
  SetCommTimeouts(handle, &timeouts);

  size_t offset = 0;
  while (offset < data.size()) {
    DWORD written = 0;
    const DWORD chunk =
        static_cast<DWORD>((std::min)(data.size() - offset, static_cast<size_t>(4096)));
    if (!WriteFile(handle, data.data() + offset, chunk, &written, nullptr) ||
        written == 0) {
      CloseHandle(handle);
      return false;
    }
    offset += written;
  }

  FlushFileBuffers(handle);
  CloseHandle(handle);
  return true;
}

}  // namespace

void EscposEnginePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "escpos_engine",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<EscposEnginePlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

EscposEnginePlugin::EscposEnginePlugin() {}

EscposEnginePlugin::~EscposEnginePlugin() {}

void EscposEnginePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string &method = method_call.method_name();

  if (method == "getPlatformVersion") {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));
    return;
  }

  if (method == "listPrinters") {
    result->Success(flutter::EncodableValue(ListPrinterNames()));
    return;
  }

  if (method == "listSerialPorts") {
    result->Success(flutter::EncodableValue(ListSerialPorts()));
    return;
  }

  if (method == "printRaw") {
    const auto *args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args == nullptr) {
      result->Error("invalid_args", "printRaw expects a map of arguments");
      return;
    }

    const auto name_it = args->find(flutter::EncodableValue("printerName"));
    const auto data_it = args->find(flutter::EncodableValue("data"));
    if (name_it == args->end() || data_it == args->end()) {
      result->Error("invalid_args", "printRaw requires printerName and data");
      return;
    }

    const auto *printer_name = std::get_if<std::string>(&name_it->second);
    const auto *data = std::get_if<std::vector<uint8_t>>(&data_it->second);
    if (printer_name == nullptr || data == nullptr) {
      result->Error("invalid_args",
                    "printerName must be a string and data must be Uint8List");
      return;
    }
    if (printer_name->empty() || data->empty()) {
      result->Error("invalid_args", "printerName/data must not be empty");
      return;
    }

    if (!PrintRawBytes(Utf8ToWide(*printer_name), *data)) {
      result->Error("print_failed", FormatWindowsError("WritePrinter"));
      return;
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "writeSerial") {
    const auto *args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args == nullptr) {
      result->Error("invalid_args", "writeSerial expects a map of arguments");
      return;
    }

    const auto port_it = args->find(flutter::EncodableValue("portName"));
    const auto data_it = args->find(flutter::EncodableValue("data"));
    if (port_it == args->end() || data_it == args->end()) {
      result->Error("invalid_args", "writeSerial requires portName and data");
      return;
    }

    const auto *port_name = std::get_if<std::string>(&port_it->second);
    const auto *data = std::get_if<std::vector<uint8_t>>(&data_it->second);
    if (port_name == nullptr || data == nullptr) {
      result->Error("invalid_args",
                    "portName must be a string and data must be Uint8List");
      return;
    }
    if (port_name->empty() || data->empty()) {
      result->Error("invalid_args", "portName/data must not be empty");
      return;
    }

    int64_t baud = 9600;
    const auto baud_it = args->find(flutter::EncodableValue("baudRate"));
    if (baud_it != args->end()) {
      if (const auto *b = std::get_if<int32_t>(&baud_it->second)) {
        baud = *b;
      } else if (const auto *b64 = std::get_if<int64_t>(&baud_it->second)) {
        baud = *b64;
      }
    }
    if (baud <= 0) {
      result->Error("invalid_args", "baudRate must be positive");
      return;
    }

    if (!WriteSerialBytes(Utf8ToWide(*port_name), *data,
                          static_cast<DWORD>(baud))) {
      result->Error("print_failed", FormatWindowsError("WriteFile/COM"));
      return;
    }
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (method == "isPrinterReady") {
    const auto *args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args == nullptr) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    const auto name_it = args->find(flutter::EncodableValue("printerName"));
    if (name_it == args->end()) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    const auto *printer_name = std::get_if<std::string>(&name_it->second);
    if (printer_name == nullptr || printer_name->empty()) {
      result->Success(flutter::EncodableValue(false));
      return;
    }
    result->Success(
        flutter::EncodableValue(IsPrinterReady(Utf8ToWide(*printer_name))));
    return;
  }

  result->NotImplemented();
}

}  // namespace escpos_engine
