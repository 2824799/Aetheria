pub mod api;
mod frb_generated;

pub mod audio;
pub mod database;
pub mod library;
pub mod models;

/// Hands the Android application context to `ndk-context` so cpal/oboe can
/// reach the audio service. Called once from `MainActivity`.
#[cfg(target_os = "android")]
#[no_mangle]
pub unsafe extern "C" fn Java_com_aetheria_aetheria_MainActivity_initAudioContext(
    env: jni::JNIEnv,
    _class: jni::objects::JClass,
    context: jni::objects::JObject,
) {
    // Unwinding across the JNI boundary is undefined behaviour, so failures
    // are logged and audio simply stays unavailable.
    let (Ok(jvm), Ok(global_context)) = (env.get_java_vm(), env.new_global_ref(context)) else {
        eprintln!("initAudioContext: failed to capture the Android context");
        return;
    };
    let java_vm_ptr = jvm.get_java_vm_pointer() as *mut std::ffi::c_void;
    let context_ptr = global_context.as_obj().as_raw() as *mut std::ffi::c_void;
    ndk_context::initialize_android_context(java_vm_ptr, context_ptr);
    // The context must outlive the process; leak the global reference.
    std::mem::forget(global_context);
}
