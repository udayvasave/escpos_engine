#include "include/escpos_engine/escpos_engine_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "escpos_engine_plugin.h"

void EscposEnginePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  escpos_engine::EscposEnginePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
