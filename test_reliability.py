#!/usr/bin/env python3
"""Offline regression checks: python3 test_reliability.py (loopback UDP only)."""
import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
from contextlib import contextmanager
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_loader("govee", loader=None)
g = importlib.util.module_from_spec(spec)
exec((ROOT / "bin/omarchy-govee").read_text(), g.__dict__)
DEVS = [{"name": "Desk Lamp", "mac": "AA:01", "sku": "H600C", "ip": None},
        {"name": "Shelf Lamp", "mac": "AA:02", "sku": "H600C", "ip": None}]


@contextmanager
def scratch():
    with tempfile.TemporaryDirectory() as tmp, patch.object(g, "CONFIG", tmp), \
            patch.object(g, "CACHE", tmp), patch.object(g, "devices", return_value=DEVS), \
            patch.dict(os.environ, XDG_RUNTIME_DIR=tmp):
        yield Path(tmp)


def rejected(fn):
    try:
        fn()
    except (g.GoveeError, ValueError):
        return
    raise AssertionError("Expected rejection")


def test_config_preserved_and_reads_do_not_write():
    with scratch() as tmp:
        assert g.load_scenes() == g.DEFAULT_SCENES
        assert not (tmp / 'scenes.json').exists()
        for invalid in ('{broken', 'null', '[]'):
            (tmp / 'scenes.json').write_text(invalid)
            rejected(g.load_scenes)
            assert (tmp / 'scenes.json').read_text() == invalid
        g.write_json(g.rooms_path(), {'office': 'Desk Lamp'})
        rejected(g.load_rooms)
        g.write_json(g.labels_path(), {'Desk Lamp': 123})
        rejected(g.load_labels)


def test_duplicate_names_and_mac_precedence():
    with scratch():
        with patch.object(g, 'devices', return_value=[DEVS[0], dict(DEVS[1], name='Desk Lamp')]):
            rejected(lambda: g.resolve('Desk Lamp'))
        g.write_json(g.labels_path(), {'Desk Lamp': 'AA:02', 'Shelf Lamp': 'Desk Lamp'})
        assert g.resolve('AA:02')['mac'] == 'AA:02'
        rejected(lambda: g.resolve('Desk Lamp'))


def test_scene_preflight_and_partial_results():
    with scratch(), patch.object(g, 'apply') as apply:
        for steps in ([{'power': 1}, {'brightness': 999}],
                      [{'power': 1}, {'color': 'bad-colour'}],
                      [{'power': 1}, {'target': 'missing', 'power': 0}],
                      [{'power': '0'}], [{'brighness': 40}], []):
            g.write_json(g.scenes_path(), {'bad': steps})
            rejected(lambda: g.run_scene('bad'))
            apply.assert_not_called()
        g.write_json(g.scenes_path(), {'ok': [{'target': 'all', 'power': 1}]})
        apply.side_effect = [g.GoveeError('offline'), {'device': 'AA:02', 'status': 'unverified'}]
        result = g.run_scene('ok')
        assert not result['ok'] and [r['status'] for r in result['results']] == ['failed', 'unverified']
    with scratch(), patch.object(g, 'lan_send') as send, patch.object(g, 'cloud') as cloud:
        for kind, value in [('brightness', 101), ('brightness', True), ('power', 2), ('color', -1)]:
            rejected(lambda: g.apply(DEVS[0], kind, value))
        send.assert_not_called()
        cloud.assert_not_called()


def test_lan_confirmation_fallback_and_cloud_error():
    with scratch(), patch.object(g, 'lan_send') as send, patch.object(g, 'lan_state') as state, \
            patch.object(g.time, 'sleep'), patch.object(g, 'cloud', return_value={'code': 200}) as cloud:
        dev = dict(DEVS[0], ip='127.0.0.1')
        state.return_value = None
        result = g.apply(dev, 'power', 1)
        assert result['status'] == 'unverified' and result['transport'] == 'cloud'
        assert send.call_count == 2 and cloud.call_count == 1
        cloud.reset_mock()
        state.return_value = {'onOff': 0, 'color': {'r': 255, 'g': 0, 'b': 0}}
        assert g.apply(dev, 'power', 0)['status'] == 'confirmed'
        assert g.apply(dev, 'color', 0xFF0000)['status'] == 'confirmed'
        cloud.assert_not_called()
        state.return_value = None
        cloud.side_effect = g.GoveeError('cloud unavailable')
        assert g.execute([(dev, 'power', 1)])['results'][0]['status'] == 'failed'


def test_mac_migration_survives_rename():
    with scratch() as tmp:
        g.write_json(g.rooms_path(), {'office': ['Desk Lamp']})
        g.write_json(g.labels_path(), {'Desk Lamp': 'My Desk'})
        g.write_json(str(tmp / 'default.json'), {'name': 'Desk Lamp'})
        g.write_json(g.scenes_path(), {'desk': [{'target': 'Desk Lamp', 'power': 1}]})
        g.migrate_ids()
        assert g.load_rooms() == {'office': ['AA:01']}
        assert g.load_labels() == {'AA:01': 'My Desk'}
        assert (tmp / 'rooms.json.before-ids').exists()
        with patch.object(g, 'devices', return_value=[dict(DEVS[0], name='Renamed'), DEVS[1]]):
            assert g.resolve()['mac'] == 'AA:01'
            assert g.resolve('My Desk')['mac'] == 'AA:01'
            assert g.resolve_many('room:office')[0]['mac'] == 'AA:01'
            assert g.scene_plan('desk')[0][0]['mac'] == 'AA:01'
        g.migrate_ids()  # repeat preserves the original backup
        assert json.loads((tmp / 'rooms.json.before-ids').read_text()) == {'office': ['Desk Lamp']}


def seed_cache(tmp):
    devs = [{'device': f'AA:{i:02}', 'deviceName': f'Lamp {i}', 'sku': 'H600C'} for i in range(12)]
    (tmp / 'devices.json').write_text(json.dumps({'fetched': time.time(), 'devices': devs}))
    return dict(os.environ, OMAGOVEE_CONFIG=str(tmp), OMAGOVEE_CACHE=str(tmp))


def test_parallel_config_edits():
    with tempfile.TemporaryDirectory() as directory:
        tmp = Path(directory)
        env = seed_cache(tmp)
        jobs = [subprocess.Popen([sys.executable, str(ROOT / 'bin/omarchy-govee'), 'label', f'AA:{i:02}', f'Label {i}'],
                                 env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for i in range(12)]
        for job in jobs:
            out, err = job.communicate(timeout=20)
            assert job.returncode == 0, err
        labels = json.loads((tmp / 'labels.json').read_text())
        assert len(labels) == 12, labels
        assert not list(tmp.glob('*.tmp'))


def test_lan_reply_serialization_and_packet_filtering():
    """Two fake lamps send unicast replies to the one protocol reply port."""
    with scratch(), patch.object(g, 'local_ip', return_value='127.0.0.1'):
        lamps, threads = [], []
        try:
            for ip in ('127.0.0.2', '127.0.0.3'):
                lamp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                lamp.bind((ip, g.PORT_CMD))
                lamp.settimeout(5)
                lamps.append(lamp)
                def reply(sock=lamp):
                    sock.recvfrom(4096)
                    for payload in ({'msg': []}, {'msg': {'cmd': 'scan', 'data': {'onOff': 0}}}):
                        sock.sendto(json.dumps(payload).encode(), ('127.0.0.1', g.PORT_RX))
                    time.sleep(0.05)
                    sock.sendto(json.dumps(g.lan_payload('devStatus', {'onOff': 1})).encode(),
                                ('127.0.0.1', g.PORT_RX))
                thread = threading.Thread(target=reply)
                thread.start()
                threads.append(thread)
            with concurrent.futures.ThreadPoolExecutor(2) as pool:
                results = list(pool.map(g.lan_state, ['127.0.0.2', '127.0.0.3']))
            assert results == [{'onOff': 1}, {'onOff': 1}], results
        finally:
            for thread in threads:
                thread.join(6)
            for lamp in lamps:
                lamp.close()


def test_labels_clear_legacy_and_unassigned_targets():
    with scratch():
        g.write_json(g.labels_path(), {'Desk Lamp': 'Old label'})
        g.set_label('AA:01', '')
        assert g.load_labels() == {}
        g.write_json(g.rooms_path(), {'office': ['Desk Lamp']})
        assert [d['mac'] for d in g.resolve_many('room:other')] == ['AA:02']
        g.main(['rooms', 'assign', 'office', 'AA:02'])
        assert g.load_rooms() == {'office': ['AA:01', 'AA:02']}
        rejected(lambda: g.resolve_many('room:other'))


def test_cloud_state_unknown_offline_and_rgb():
    with scratch(), patch.object(g, 'cloud') as cloud:
        cloud.return_value = {'payload': {'capabilities': []}}
        assert g.power_state(DEVS[0])['online'] is None
        assert g.power_state(DEVS[0])['power'] is None
        assert 'error' in g.power_state(DEVS[0])
        caps = [{'instance': 'online', 'state': {'value': True}},
                {'instance': 'colorRgb', 'state': {'value': 0xFF0000}},
                {'instance': 'powerSwitch', 'state': {'value': 1}}]
        cloud.return_value = {'payload': {'capabilities': caps}}
        assert g.power_state(DEVS[0])['color'] == {'r': 255, 'g': 0, 'b': 0}
        caps[0]['state']['value'] = False
        assert g.power_state(DEVS[0])['power'] is None
        assert g.power_state(DEVS[0])['color'] is None
        for invalid in (None, [], {'capabilities': None}, {'capabilities': [{}]}):
            cloud.return_value = {'payload': invalid}
            rejected(lambda: g.power_state(DEVS[0]))


if __name__ == '__main__':
    for name, fn in sorted(list(globals().items())):
        if name.startswith('test_'):
            fn()
            print('ok ', name)
    print('all passed')
