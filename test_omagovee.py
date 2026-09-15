#!/usr/bin/env python3
"""Self-check for the payload/colour logic — the parts that silently produce a
light doing the wrong thing rather than an error. Run: python3 test_omagovee.py

Transport is not covered: it needs a real lamp on the LAN.
"""

import os
import importlib.util
import json
import socket
import struct
import threading

spec = importlib.util.spec_from_loader("govee", loader=None)
govee = importlib.util.module_from_spec(spec)
exec(open("bin/omarchy-govee").read(), govee.__dict__)


def test_cloud_payload():
    got = govee.cloud_payload("H605C", "AA:BB", "devices.capabilities.on_off",
                              "powerSwitch", 1, req_id="t")
    assert got == {
        "requestId": "t",
        "payload": {"sku": "H605C", "device": "AA:BB",
                    "capability": {"type": "devices.capabilities.on_off",
                                   "instance": "powerSwitch", "value": 1}},
    }, got


def test_lan_payload():
    assert govee.lan_payload("turn", {"value": 1}) == {
        "msg": {"cmd": "turn", "data": {"value": 1}}}


def test_colours():
    assert govee.parse_color("ff8800") == 0xFF8800
    assert govee.parse_color("#FF8800") == 0xFF8800
    assert govee.parse_color("RED") == 0xFF0000
    for bad in ("nosuchcolour", "1000000", "-1"):
        try:
            govee.parse_color(bad)
        except ValueError:
            continue
        raise AssertionError("accepted bad colour %r" % bad)


def test_rgb_split():
    assert govee.rgb(0xFF8800) == {"r": 255, "g": 136, "b": 0}
    assert govee.rgb(0x000000) == {"r": 0, "g": 0, "b": 0}
    assert govee.rgb(0xFFFFFF) == {"r": 255, "g": 255, "b": 255}


def test_lan_send_reaches_the_wire():
    """A fake lamp on 127.0.0.1:4003 — catches a malformed packet or a wrong
    port, which is otherwise invisible: UDP never complains."""
    lamp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    lamp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    lamp.bind(("127.0.0.1", govee.PORT_CMD))
    lamp.settimeout(2)
    got = []
    listener = threading.Thread(target=lambda: got.append(lamp.recvfrom(4096)[0]))
    listener.start()
    govee.lan_send("127.0.0.1", "brightness", {"value": 42})
    listener.join(3)
    lamp.close()
    assert got, "nothing arrived on port %d" % govee.PORT_CMD
    assert json.loads(got[0]) == {"msg": {"cmd": "brightness", "data": {"value": 42}}}


def test_device_kind_prefers_the_longest_prefix():
    """H6072 is a floor lamp inside the H60 bulb range: a plain startswith scan
    in dict order would call it a bulb depending on insertion order."""
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        govee.CONFIG = tmp
        assert govee.device_kind("H6072") == "lamp"
        assert govee.device_kind("H600C") == "bulb"
        assert govee.device_kind("H615A") == "strip"
        assert govee.device_kind("H9999") == "bulb"          # unknown -> bulb
        govee.write_json(os.path.join(tmp, "icons.json"), {"H615A": "lamp"})
        assert govee.device_kind("H615A") == "lamp"          # override wins


def test_assign_room_moves_rather_than_copies():
    """A device in two rooms fires twice for one `room:` command and draws
    twice in the panel, so assignment must remove it from its old room."""
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        govee.CONFIG = tmp
        govee.write_json(govee.rooms_path(), {"old": ["a", "b"], "keep": ["c"]})
        rooms = govee.assign_room("new", ["a"])
        assert rooms == {"old": ["b"], "keep": ["c"], "new": ["a"]}, rooms
        rooms = govee.assign_room("none", ["b"])
        assert "old" not in rooms, rooms          # empty room disappears
        assert rooms == {"keep": ["c"], "new": ["a"]}, rooms


DEVS = [{"name": n, "mac": "M" + n, "sku": "H600C", "ip": None}
        for n in ("lvrt1", "lvrt10", "shelf1")]


def fresh_config(rooms=None):
    """Temp config with a fixed device list, so room commands run without the
    Govee API. Use as a context manager; the dir goes away on exit."""
    import tempfile
    tmp = tempfile.TemporaryDirectory()
    govee.CONFIG = tmp.name
    govee.devices = lambda: DEVS
    if rooms is not None:
        govee.write_json(govee.rooms_path(), rooms)
    return tmp


def exits(fn):
    import contextlib
    import io
    try:
        with contextlib.redirect_stdout(io.StringIO()), \
             contextlib.redirect_stderr(io.StringIO()):
            fn()
    except SystemExit:
        return True
    return False


def run(*argv):
    import contextlib
    import io
    with contextlib.redirect_stdout(io.StringIO()):
        govee.main(list(argv))


def rooms_on_disk():
    return open(govee.rooms_path()).read()


def test_load_rooms_repairs_duplicates():
    """A device in two rooms (written by an older CLI) keeps its first room.
    The repair is in memory: `dump` reads every minute and must not write."""
    with fresh_config({"a": ["x", "y", "x"], "b": ["x"], "c": ["y"]}):
        before = rooms_on_disk()
        assert govee.load_rooms() == {"a": ["x", "y"]}, govee.load_rooms()
        assert rooms_on_disk() == before


def test_rooms_shorthand_moves():
    with fresh_config({"hall": ["lvrt1"]}):
        run("rooms", "office", "lvrt1")
        assert govee.read_json(govee.rooms_path()) == {"office": ["lvrt1"]}


def test_assign_ignores_repeats():
    with fresh_config():
        run("rooms", "assign", "a", "shelf1", "shelf1")
        assert govee.read_json(govee.rooms_path()) == {"a": ["shelf1"]}


def test_reserved_room_names_refused():
    """none/other/all already mean something; a room with one of those names
    cannot be targeted, and `other` would unassign on drop in the panel."""
    with fresh_config({"a": ["lvrt1"]}):
        before = rooms_on_disk()
        for argv in (["rooms", "assign", "other", "shelf1"],
                     ["rooms", "assign", "ALL", "shelf1"],
                     ["rooms", "assign", "  ", "shelf1"],
                     ["rooms", "rename", "a", "none"]):
            assert exits(lambda: govee.main(argv)), argv
        assert rooms_on_disk() == before


def test_rename_onto_existing_refused():
    """Renaming onto an existing room used to replace its members silently."""
    with fresh_config({"a": ["lvrt1"], "b": ["shelf1"]}):
        before = rooms_on_disk()
        assert exits(lambda: govee.main(["rooms", "rename", "a", "b"]))
        assert rooms_on_disk() == before


def test_resolve_exact_beats_substring():
    """`lvrt1` is a substring of `lvrt10`: first-match used to pick either."""
    with fresh_config():
        assert govee.resolve("lvrt1")["name"] == "lvrt1"
        assert govee.resolve("LVRT10")["name"] == "lvrt10"
        assert govee.resolve("shelf")["name"] == "shelf1"
        assert exits(lambda: govee.resolve("lvrt"))


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok  %s" % name)
    print("all passed")
