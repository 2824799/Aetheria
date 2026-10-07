#!/usr/bin/env python3
"""Check native lyrics against an active fullscreen window on real KWin."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from gi.repository import Gio, GLib


def main():
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    name = bus.get_unique_name()
    plugin = f"aetheria-stacking-test-{os.getpid()}"
    interface = Gio.DBusNodeInfo.new_for_xml("""
      <node><interface name="org.aetheria.DesktopTest">
        <method name="Check"><arg type="s" direction="in"/>
          <arg type="b" direction="in"/><arg type="b" direction="in"/></method>
        <method name="Report"><arg type="s" direction="in"/></method>
      </interface></node>""").interfaces[0]
    loop = GLib.MainLoop()
    pending = None
    failure = None

    def scripting(method, signature, args, reply_signature):
        return bus.call_sync(
            "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting", method,
            GLib.Variant(signature, args), GLib.VariantType.new(reply_signature),
            Gio.DBusCallFlags.NONE, 5000, None).unpack()[0]

    with tempfile.TemporaryDirectory(prefix="aetheria-kwin-stacking-") as tmp:
        script = Path(tmp) / "probe.js"

        def handle(_bus, _sender, _path, _interface, method, params, invocation):
            nonlocal pending, failure
            try:
                if method == "Check":
                    assert pending is None
                    phase, above, fullscreen = params.unpack()
                    pending = (invocation, phase, above, fullscreen)
                    scripting("unloadScript", "(s)", (plugin,), "(b)")
                    script.write_text("""
                        const windows = workspace.stackingOrder.map(w => ({
                            caption: w.caption, pid: w.pid,
                            resourceClass: String(w.resourceClass),
                            fullscreen: w.fullScreen,
                            active: w === workspace.activeWindow
                        })).filter(w => w.pid === %d);
                        callDBus(%s, '/org/aetheria/DesktopTest',
                            'org.aetheria.DesktopTest', 'Report', JSON.stringify(windows));
                    """ % (child.pid, json.dumps(name)))
                    script_id = scripting("loadScript", "(ss)", (str(script), plugin), "(i)")
                    assert script_id >= 0, "KWin could not load stacking probe"
                    bus.call_sync(
                        "org.kde.KWin", f"/Scripting/Script{script_id}",
                        "org.kde.kwin.Script", "run", None, None,
                        Gio.DBusCallFlags.NONE, 5000, None)
                else:
                    windows = json.loads(params.unpack()[0])
                    check, phase, above, fullscreen = pending
                    fixture = [i for i, w in enumerate(windows) if
                               w["caption"] == "Aetheria fullscreen regression fixture"
                               and w["pid"] == child.pid]
                    lyrics = [i for i, w in enumerate(windows) if
                              w["caption"] == ""
                              and w["pid"] == child.pid]
                    assert len(fixture) == len(lyrics) == 1, windows
                    game = windows[fixture[0]]
                    assert game["active"], f"{phase}: lyrics stole focus"
                    assert game["fullscreen"] == fullscreen, f"{phase}: fullscreen mismatch"
                    assert (lyrics[0] > fixture[0]) == above, f"{phase}: wrong stacking order"
                    print(f"KWin: {phase}: lyrics {'above' if above else 'below'}, fixture retains focus",
                          flush=True)
                    check.return_value(GLib.Variant("()", ()))
                    pending = None
                    invocation.return_value(GLib.Variant("()", ()))
            except Exception as error:
                failure = str(error)
                invocation.return_dbus_error("org.aetheria.DesktopTest.Failed", failure)
                if pending is not None and pending[0] != invocation:
                    pending[0].return_dbus_error("org.aetheria.DesktopTest.Failed", failure)
                pending = None

        registration = bus.register_object(
            "/org/aetheria/DesktopTest", interface, handle, None, None)
        env = os.environ.copy()
        env.update(GDK_BACKEND="wayland", AETHERIA_TEST_PROBE=name)
        child = subprocess.Popen([sys.argv[1], "fullscreen"], env=env)

        def poll_child():
            if child.poll() is None:
                return True
            loop.quit()
            return False

        def timeout():
            nonlocal failure
            failure = "Fullscreen stacking test timed out"
            loop.quit()
            return False

        GLib.timeout_add(50, poll_child)
        GLib.timeout_add_seconds(30, timeout)
        try:
            loop.run()
        finally:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            scripting("unloadScript", "(s)", (plugin,), "(b)")
            bus.unregister_object(registration)
        if failure or child.returncode:
            raise SystemExit(failure or f"Fixture exited with {child.returncode}")


if __name__ == "__main__":
    main()
