#!/usr/bin/env python3
"""ABI smoke test for the ImageGlass-Ithmb-Plugin.

Loads the built cdylib through its real C entry point (``ig_plugin_get_api``)
-- the exact surface ImageGlass v10 uses -- and exercises the full codec path:
entry -> initialize -> get_codec -> can_handle_extension -> load_metadata
-> decode_static_raster -> free_pixel_buffer.

This validates the binary ABI contract (struct layout, calling convention,
status codes) end to end WITHOUT the ImageGlass GUI, so it can be run by an
agent or in CI on every release.

Usage:
    cargo build --release
    python3 scripts/abi-smoke.py [path/to/file.ithmb]

Exit 0 with a decode summary on success; non-zero with a diagnostic on any
ABI or decode failure.
"""

import ctypes
import os
import sys

from ctypes import (
    CFUNCTYPE,
    POINTER,
    Structure,
    byref,
    c_int32,
    c_int64,
    c_ubyte,
    c_uint16,
    c_void_p,
    cast,
    sizeof,
)

SO_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..",
    "target",
    "release",
    "libithmb_core_cabi.so",
)
ABI_VERSION = 1_000_000  # IG_PLUGIN_ABI_VERSION (major = version // 1_000_000)

STATUS = {
    0: "Ok",
    1: "Unsupported",
    2: "Canceled",
    3: "InvalidArg",
    4: "DecodeFailed",
    5: "OutOfMemory",
    6: "Internal",
    7: "NotImplemented",
    8: "IoError",
    9: "EncodeFailed",
}


def fail(msg, code=1):
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(code)


# --------------------------------------------------------------------------
# ABI structs -- mirror src/types.rs. Offsets verified by the plugin's own
# test_abi_struct_sizes (IGCodecApi == 112, IGCodecCapability == 104).
# --------------------------------------------------------------------------


class IGStringRef(Structure):
    _fields_ = [
        ("data", POINTER(c_uint16)),
        ("length", c_int32),
    ]


class IGHostCoreApi(Structure):
    _fields_ = [("_opaque", c_ubyte)]  # host services; unused by the smoke path


class IGHostApi(Structure):
    _fields_ = [
        ("struct_size", c_int32),
        ("abi_version", c_int32),
        ("core", POINTER(IGHostCoreApi)),
    ]


class IGPluginInfo(Structure):
    _fields_ = [
        ("plugin_id", IGStringRef),
        ("name", IGStringRef),
        ("version", IGStringRef),
        ("abi_version", c_int32),
        ("codec_count", c_int32),
    ]


class IGCodecCapability(Structure):
    _fields_ = [
        ("struct_size", c_int32),
        ("codec_id", IGStringRef),
        ("codec_name", IGStringRef),
        ("metadata_priority", c_int32),
        ("decode_priority", c_int32),
        ("supports_metadata", c_int32),
        ("supports_color_profiles", c_int32),
        ("supports_static_raster_decoding", c_int32),
        ("supports_animation_decoding", c_int32),
        ("decode_extension_count", c_int32),
        ("decode_extensions", POINTER(IGStringRef)),
        ("supports_static_raster_encoding", c_int32),
        ("supports_multi_frame_encoding", c_int32),
        ("encode_priority", c_int32),
        ("encode_extension_count", c_int32),
        ("encode_extensions", POINTER(IGStringRef)),
    ]


class IGImageInfo(Structure):
    _fields_ = [
        ("width", c_int32),
        ("height", c_int32),
        ("pixel_format", c_int32),
        ("has_alpha", c_int32),
        ("hdr_transfer_fn", c_int32),
        ("color_space", c_int32),
        ("orientation", c_int32),
        ("frame_count", c_int32),
        ("file_size_bytes", c_int64),
        ("icc_profile_data", POINTER(c_ubyte)),
        ("icc_profile_size", c_int32),
    ]


class IGPixelBuffer(Structure):
    _fields_ = [
        ("data", POINTER(c_ubyte)),
        ("width", c_int32),
        ("height", c_int32),
        ("stride", c_int32),
        ("pixel_format", c_int32),
        ("release_context", c_void_p),
    ]


# Function-pointer table types (signatures from src/types.rs).
GET_CODEc_T = CFUNCTYPE(c_int32, c_int32, POINTER(c_void_p))
INIT_T = CFUNCTYPE(c_int32)
SELF_TEST_T = CFUNCTYPE(c_int32)
SHUTDOWN_T = CFUNCTYPE(None)
GET_CAP_T = CFUNCTYPE(c_int32, POINTER(POINTER(IGCodecCapability)))
CAN_HANDLE_EXT_T = CFUNCTYPE(c_int32, IGStringRef)
CAN_HANDLE_SIG_T = CFUNCTYPE(c_int32, POINTER(c_ubyte), c_int32)
LOAD_META_T = CFUNCTYPE(c_int32, IGStringRef, POINTER(IGImageInfo), c_void_p)
DECODE_T = CFUNCTYPE(c_int32, IGStringRef, c_int32, POINTER(IGPixelBuffer), c_void_p)
FREE_PB_T = CFUNCTYPE(None, POINTER(IGPixelBuffer))


class IGPluginApi(Structure):
    _fields_ = [
        ("struct_size", c_int32),
        ("abi_version", c_int32),
        ("info", IGPluginInfo),
        ("get_codec", GET_CODEc_T),
        ("initialize", INIT_T),
        ("shutdown", SHUTDOWN_T),
        ("self_test", SELF_TEST_T),
    ]


class IGCodecApi(Structure):
    _fields_ = [
        ("struct_size", c_int32),
        ("get_capability", GET_CAP_T),
        ("can_handle_extension", CAN_HANDLE_EXT_T),
        ("can_handle_signature", CAN_HANDLE_SIG_T),
        ("load_metadata", LOAD_META_T),
        ("decode_static_raster", DECODE_T),
        ("free_pixel_buffer", FREE_PB_T),
        ("get_animation_info", LOAD_META_T),
        ("free_animation_info", FREE_PB_T),
        ("decode_animation_frame", DECODE_T),
        ("encode_static_raster", LOAD_META_T),
        ("begin_encode_multi_frame", LOAD_META_T),
        ("encode_frame", LOAD_META_T),
        ("end_encode_multi_frame", LOAD_META_T),
    ]


def utf16_ref(text):
    """Build an IGStringRef for `text` (case-insensitive length-based match)."""
    buf = (c_uint16 * (len(text) + 1))(
        *[ord(c) for c in text], 0
    )  # +1 NUL keeps buffers alive; length excludes it
    return buf, IGStringRef(cast(buf, POINTER(c_uint16)), len(text))


def read_utf16(ref):
    """Read an IGStringRef back into a str."""
    if not ref.data or ref.length <= 0:
        return ""
    chars = [ref.data[i] for i in range(ref.length)]
    return "".join(chr(c) for c in chars)


def main():
    if not os.path.exists(SO_PATH):
        fail(f"cdylib not found at {SO_PATH} -- run `cargo build --release` first")
    fixture = (
        sys.argv[1]
        if len(sys.argv) > 1
        else os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            "..",
            "tests",
            "fixtures",
            "test1.ithmb",
        )
    )
    if not os.path.exists(fixture):
        fail(f"fixture not found: {fixture}")

    lib = ctypes.CDLL(SO_PATH)
    lib.ig_plugin_get_api.restype = POINTER(IGPluginApi)
    lib.ig_plugin_get_api.argtypes = [c_int32, POINTER(IGHostApi)]

    # 1. Entry point (what ImageGlass calls first)
    host = IGHostApi(sizeof(IGHostApi), ABI_VERSION, None)
    api_ptr = lib.ig_plugin_get_api(ABI_VERSION, byref(host))
    if not api_ptr:
        fail("ig_plugin_get_api returned NULL (ABI version mismatch or init failure)")
    api = api_ptr.contents
    print(
        f"plugin: {read_utf16(api.info.name)} v{read_utf16(api.info.version)} "
        f"(abi_version={api.abi_version}, struct_size={api.struct_size}, "
        f"codecs={api.info.codec_count})"
    )

    # 2. initialize
    st = api.initialize()
    if st != 0:
        fail(f"initialize -> {STATUS.get(st, st)}")

    # 3. enumerate codec 0
    codec_raw = c_void_p()
    st = api.get_codec(0, byref(codec_raw))
    if st != 0:
        fail(f"get_codec(0) -> {STATUS.get(st, st)}")
    codec = cast(codec_raw, POINTER(IGCodecApi)).contents
    if codec.struct_size != 112:
        fail(f"IGCodecApi struct_size={codec.struct_size} (expected 112)")

    # 4. capability surface
    cap_ptr = POINTER(IGCodecCapability)()
    st = codec.get_capability(byref(cap_ptr))
    if st != 0:
        fail(f"get_capability -> {STATUS.get(st, st)}")
    cap = cap_ptr.contents
    exts = []
    for i in range(cap.decode_extension_count):
        exts.append(read_utf16(cap.decode_extensions[i]))
    print(
        f"codec: {read_utf16(cap.codec_name)} extensions={exts} "
        f"static_decode={cap.supports_static_raster_decoding}"
    )

    # 5. can_handle_extension
    ext_buf, ext_ref = utf16_ref(".ithmb")
    if codec.can_handle_extension(ext_ref) != 1:
        fail("can_handle_extension('.ithmb') -> 0 (expected 1)")
    print("can_handle_extension('.ithmb') -> 1")

    # 6. load_metadata
    path_buf, path_ref = utf16_ref(fixture)
    info = IGImageInfo()
    st = codec.load_metadata(path_ref, byref(info), None)
    if st != 0:
        fail(f"load_metadata -> {STATUS.get(st, st)}")
    print(
        f"metadata: {info.width}x{info.height} frames={info.frame_count} "
        f"pixel_format={info.pixel_format} bytes={info.file_size_bytes}"
    )

    # 7. decode_static_raster (frame 0)
    pb = IGPixelBuffer()
    st = codec.decode_static_raster(path_ref, 0, byref(pb), None)
    if st != 0:
        fail(f"decode_static_raster -> {STATUS.get(st, st)}")
    if not pb.data or pb.width <= 0 or pb.height <= 0 or pb.stride <= 0:
        fail(
            f"decode returned invalid pixel buffer {pb.width}x{pb.height} stride={pb.stride}"
        )
    expected = pb.height * pb.stride
    raw = ctypes.string_at(pb.data, expected)
    print(
        f"decoded: {pb.width}x{pb.height} stride={pb.stride} format={pb.pixel_format} "
        f"buffer={len(raw)} bytes"
    )
    if len(raw) < pb.width * pb.height:
        fail("decoded buffer smaller than w*h")

    # 8. free
    codec.free_pixel_buffer(byref(pb))
    api.shutdown()
    print(
        "PASS: plugin ABI smoke test (entry -> init -> codec -> metadata -> decode -> free)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
