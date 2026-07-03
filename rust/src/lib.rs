pub mod api;
mod frb_generated;

pub mod audio;
pub mod database;
pub mod models;

#[cfg(target_os = "android")]
#[no_mangle]
pub unsafe extern "C" fn Java_com_aetheria_aetheria_MainActivity_initAudioContext(
    mut env: jni::JNIEnv,
    _class: jni::objects::JClass,
    context: jni::objects::JObject,
) {
    let jvm = env.get_java_vm().unwrap();
    let java_vm_ptr = jvm.get_java_vm_pointer() as *mut std::ffi::c_void;
    
    let global_context = env.new_global_ref(context).unwrap();
    let context_ptr = global_context.as_obj().as_raw() as *mut std::ffi::c_void;
    
    ndk_context::initialize_android_context(java_vm_ptr, context_ptr);
    std::mem::forget(global_context);
}

