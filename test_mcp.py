#!/usr/bin/env python3
"""Actual stdio MCP handshake/tools against a controller with a fake cloud."""
import asyncio
import json
import os
from pathlib import Path
import sys
import tempfile
import time

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parent


async def check():
    with tempfile.TemporaryDirectory() as directory:
        tmp = Path(directory)
        (tmp / 'devices.json').write_text(json.dumps({'fetched': time.time(), 'devices': [
            {'device': 'AA:01', 'deviceName': 'Desk Lamp', 'sku': 'H600C'},
            {'device': 'AA:02', 'deviceName': 'Shelf Lamp', 'sku': 'H600C'}]}))
        (tmp / 'rooms.json').write_text(json.dumps({'office': ['AA:01', 'AA:02']}))
        fake = tmp / 'controller.py'
        fake.write_text('''import json, runpy, sys
ns = runpy.run_path(%r)
def cloud(path, body=None):
    if path.endswith('/control') and body['payload']['device'] == 'AA:02':
        ns['die']('simulated offline device')
    return {'code': 200, 'payload': {'capabilities': [
        {'instance': 'online', 'state': {'value': True}},
        {'instance': 'powerSwitch', 'state': {'value': 1}},
        {'instance': 'brightness', 'state': {'value': 42}}]}}
ns['apply'].__globals__['cloud'] = cloud
try:
    sys.exit(ns['main'](sys.argv[1:]))
except (ns['GoveeError'], ValueError) as exc:
    print(json.dumps({'ok': False, 'error': str(exc)}))
    sys.exit(1)
''' % str(ROOT / 'bin/omarchy-govee'))
        launcher = tmp / 'server.py'
        launcher.write_text('''import runpy
from pathlib import Path
ns = runpy.run_path(%r)
ns['command'].__globals__['CLI'] = Path(%r)
ns['mcp'].run(transport='stdio')
''' % (str(ROOT / 'bin/omagovee-mcp'), str(fake)))
        env = dict(os.environ, OMAGOVEE_CONFIG=str(tmp), OMAGOVEE_CACHE=str(tmp))
        server = StdioServerParameters(command=sys.executable, args=[str(launcher)], env=env)
        async with stdio_client(server) as (read, write), ClientSession(read, write) as client:
            await client.initialize()
            listed = await client.list_tools()
            assert {t.name for t in listed.tools} == {'list_devices', 'get_state', 'set_power',
                'set_brightness', 'set_color', 'list_scenes', 'run_scene'}
            result = await client.call_tool('list_devices', {})
            assert not result.isError and len(result.structuredContent['devices']) == 2
            result = await client.call_tool('get_state', {'target': 'AA:01'})
            assert result.structuredContent['devices'][0]['brightness'] == 42
            for percent in (-1, 101, True):
                result = await client.call_tool('set_brightness', {'target': 'AA:01', 'percent': percent})
                assert result.isError, result
            result = await client.call_tool('set_color', {'target': 'AA:01', 'color': 'nope'})
            assert result.isError
            result = await client.call_tool('set_power', {'target': 'AA:01', 'on': True})
            assert not result.isError and result.structuredContent['results'][0]['status'] == 'unverified'
            result = await client.call_tool('set_power', {'target': 'room:office', 'on': False})
            assert result.isError
            assert [r['status'] for r in result.structuredContent['results']] == ['unverified', 'failed']
            result = await client.call_tool('list_scenes', {})
            assert 'meeting' in result.structuredContent['scenes']
            result = await client.call_tool('run_scene', {'name': 'off'})
            assert result.isError and len(result.structuredContent['results']) == 2
            result = await client.call_tool('get_state', {'target': '"; touch /tmp/no-shell; "'})
            assert result.isError
    print('MCP handshake, all seven tools, validation and partial-failure checks passed')


if __name__ == '__main__':
    asyncio.run(check())
