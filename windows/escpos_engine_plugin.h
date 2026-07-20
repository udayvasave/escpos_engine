#ifndef FLUTTER_PLUGIN_ESCPOS_ENGINE_PLUGIN_H_
#define FLUTTER_PLUGIN_ESCPOS_ENGINE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace escpos_engine {

class EscposEnginePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  EscposEnginePlugin();

  virtual ~EscposEnginePlugin();

  // Disallow copy and assign.
  EscposEnginePlugin(const EscposEnginePlugin&) = delete;
  EscposEnginePlugin& operator=(const EscposEnginePlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace escpos_engine

#endif  // FLUTTER_PLUGIN_ESCPOS_ENGINE_PLUGIN_H_
