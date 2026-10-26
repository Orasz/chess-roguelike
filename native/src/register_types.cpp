#include "register_types.h"

#include <gdextension_interface.h>

#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "../bridge/sf_bridge.h"
#include "stockfish_engine.h"

using namespace godot;

void initialize_stockfish_gd_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE)
        return;
    GDREGISTER_CLASS(StockfishEngine);
}

void uninitialize_stockfish_gd_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE)
        return;
    // Join the engine thread before the library can be unloaded.
    sfbridge::stop();
}

extern "C" {

GDExtensionBool GDE_EXPORT stockfish_gd_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
                                                     GDExtensionClassLibraryPtr        p_library,
                                                     GDExtensionInitialization*        r_initialization) {
    GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_stockfish_gd_module);
    init_obj.register_terminator(uninitialize_stockfish_gd_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}

}
