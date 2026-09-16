#!/usr/bin/env python3
"""Virtual-display runtime check using the installed Omarchy shell imports and fake CLI.
Run: python3 test_menu_qml.py. Requires qs, Xvfb and OMARCHY_PATH; no real lamps used.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent


def main():
    omarchy = Path(os.environ['OMARCHY_PATH'])
    with tempfile.TemporaryDirectory(prefix='omagovee-qml-') as directory:
        tmp = Path(directory)
        shutil.copytree(ROOT / 'plugin', tmp / 'plugin')
        # X11 cannot instantiate Wayland attached properties. Only omit the
        # surface hints in this test copy; production UI/logic stays intact.
        menu_file = tmp / 'plugin/GoveeMenu.qml'
        menu_file.write_text('\n'.join(line for line in menu_file.read_text().splitlines()
                                      if not line.strip().startswith('WlrLayershell.')) + '\n')
        (tmp / 'Commons').symlink_to(omarchy / 'shell/Commons', target_is_directory=True)
        (tmp / 'Ui').symlink_to(omarchy / 'shell/Ui', target_is_directory=True)
        fake = tmp / 'omarchy-govee'
        fake.write_text('''#!/usr/bin/env python3
import json, os, sys, time
with open(os.environ['GOVEE_TEST_LOG'], 'a') as f: f.write(json.dumps(sys.argv[1:]) + '\\n')
if sys.argv[1:] == ['dump']:
    time.sleep(0.05)
    print(json.dumps({'devices':[{'name':'Desk','label':'My desk','mac':'AA:01','sku':'H600C','kind':'bulb','online':True,'power':1,'brightness':40}], 'rooms':{'Office':['AA:01']},'scenes':['evening']}))
else:
    print(json.dumps({'ok':True,'results':[{'status':'confirmed'}]}))
''')
        fake.chmod(0o755)
        ipc = tmp / 'omarchy-shell'
        ipc.write_text('#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n')
        ipc.chmod(0o755)
        launch_env = dict(os.environ, PATH=str(tmp) + os.pathsep + os.environ['PATH'])
        for argument, method in (([], 'toggle'), (['summon'], 'summon'), (['close'], 'hide')):
            launched = subprocess.run([str(ROOT / 'bin/omarchy-menu-lights'), *argument],
                                      env=launch_env, text=True, capture_output=True, check=True)
            expected = ['shell', method, 'olafkfreund.govee'] + ([] if method == 'hide' else ['{}'])
            assert json.loads(launched.stdout) == expected
        assert subprocess.run([str(ROOT / 'bin/omarchy-menu-lights'), 'invalid'],
                              env=launch_env, capture_output=True).returncode == 2
        qml = '''import QtQuick
import Quickshell
import Quickshell.X11
import "PLUGIN" as Govee
ShellRoot {
  id: test
  property int stage: 0
  property var menu: menuLoader.item
  Component.onCompleted: console.log("GOVEE_QML_START")
  function check(ok, message) { if (!ok) throw new Error(message) }
  function find(node, name) {
    if (node.objectName === name) return node
    var children = node.data || (node.contentItem ? [node.contentItem] : [])
    for (var i = 0; i < children.length; i++) {
      var found = find(children[i], name)
      if (found) return found
    }
    return null
  }
  Loader { id: menuLoader; source: "plugin/GoveeMenu.qml"; asynchronous: true }
  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      try {
        if (!menu) return
        if (test.stage === 0) { menu.open("{}"); test.stage++; return }
        if (test.stage === 1) {
          if (menu.rows.length < 4) return
          test.check(menu.opened, "menu did not open")
          menu.selected = menu.rows.findIndex(function(r) { return r.id === "AA:01" })
          var right = {key: Qt.Key_Right, modifiers: Qt.NoModifier, accepted: false}
          menu.handleKey(right)
          test.check(right.accepted, "right arrow handled")
          test.check(menu.view === "actions" && menu.target.target === "AA:01", "target navigation")
          menu.selected = 0
          menu.handleKey(right)
          test.check(!test.find(menu, "goveeClient").busy, "right arrow must not send a power command")
          var left = {key: Qt.Key_Left, modifiers: Qt.AltModifier, accepted: false}
          menu.handleKey(left)
          test.check(menu.view === "targets" && left.accepted, "alt-left back")
          menu.selected = menu.rows.findIndex(function(r) { return r.id === "AA:01" })
          right.modifiers = Qt.AltModifier
          menu.handleKey(right)
          test.check(menu.view === "actions", "alt-right opens target")
          menu.selected = 2
          menu.activate()
          test.check(menu.form === "brightness", "brightness form")
          var input = test.find(menu, "editor")
          test.check(!!input, "editor lookup")
          input.text = "101"
          menu.submit()
          test.check(menu.form === "brightness" && menu.failed, "reject invalid brightness")
          input.text = "35"
          menu.submit()
          test.check(menu.form === "", "save brightness")
          menu.selected = 4
          menu.activate()
          var escape = {key: Qt.Key_Escape, modifiers: Qt.NoModifier, accepted: false}
          menu.handleKey(escape)
          test.check(menu.form === "" && escape.accepted, "escape cancels form")
          menu.selected = 0
          menu.activate()
          menu.selected = 1
          menu.activate()
          menu.close()
          test.stage++
          return
        }
        if (test.stage === 2) {
          if (menu.message !== "Done" || test.find(menu, "goveeClient").busy) return
          test.check(!menu.opened, "actions reopened menu")
          menu.open("{}")
          test.check(menu.view === "targets", "reopen resets navigation")
          var up = {key: Qt.Key_Up, modifiers: Qt.NoModifier, accepted: false}
          menu.handleKey(up)
          test.check(menu.selected === menu.rows.length - 1 && up.accepted, "keyboard wrap selection")
          var search = test.find(menu, "search")
          search.text = "my desk"
          test.check(menu.rows.length === 1 && menu.rows[0].id === "AA:01", "search preserves ID")
          menu.back()
          test.check(search.text === "", "escape clears search")
          menu.close()
          console.log("GOVEE_QML_PASS")
          Qt.quit()
        }
      } catch (e) { console.error("GOVEE_QML_FAIL: " + e); Qt.quit() }
    }
  }
  Timer { interval: 8000; running: true; onTriggered: { console.error("GOVEE_QML_FAIL: timeout"); Qt.quit() } }
}
'''.replace('PLUGIN', 'plugin')
        (tmp / 'shell.qml').write_text(qml)
        env = dict(os.environ, QT_QPA_PLATFORM='xcb', QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='basic',
                   QT_QUICK_CONTROLS_STYLE='Basic', QSG_RENDER_LOOP='basic',
                   XDG_RUNTIME_DIR=str(tmp / 'runtime'), XDG_CACHE_HOME=str(tmp / 'cache'),
                   PATH=str(tmp) + os.pathsep + os.environ['PATH'], GOVEE_TEST_LOG=str(tmp / 'calls.jsonl'))
        env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
        env.pop('WAYLAND_DISPLAY', None)
        (tmp / 'runtime').mkdir(mode=0o700)
        display = subprocess.Popen(['Xvfb', '-displayfd', '1', '-screen', '0', '1280x800x24', '-nolisten', 'tcp'],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            number = display.stdout.readline().strip()
            assert number.isdigit(), display.stderr.read()
            env['DISPLAY'] = ':' + number
            result = subprocess.run([shutil.which('qs'), '--no-color', '-p', str(tmp / 'shell.qml')],
                                    env=env, text=True, capture_output=True, timeout=20)
        except subprocess.TimeoutExpired as exc:
            print(exc.stdout, exc.stderr)
            print('calls:', (tmp / 'calls.jsonl').read_text() if (tmp / 'calls.jsonl').exists() else 'none')
            raise
        finally:
            display.terminate()
            display.communicate(timeout=5)
        output = result.stdout + result.stderr
        print(output)
        assert result.returncode == 0 and 'GOVEE_QML_PASS' in output and 'GOVEE_QML_FAIL' not in output
        calls = [json.loads(line) for line in (tmp / 'calls.jsonl').read_text().splitlines()]
        actions = [call for call in calls if call != ['dump']]
        assert actions == [['--json','brightness','35','AA:01'], ['--json','on','AA:01'], ['--json','off','AA:01']], actions
        print('QML runtime: menu loaded, navigation, forms, queued actions and reopen passed')


if __name__ == '__main__':
    main()
