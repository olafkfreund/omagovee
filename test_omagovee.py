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


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok  %s" % name)
    print("all passed")
