pub mod api;
mod frb_generated;

pub mod audio;
pub mod database;
pub mod models;

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "C" fn __cxa_pure_virtual() {
    loop {}
}
