#!/icpc/scripts/venv/bin/python
import FreeSimpleGUI as sg
from pathlib import Path
import json
import re
import urllib.request
from urllib.parse import urlparse, quote
from subprocess import PIPE, Popen
import sys
import os
from pprint import pprint

from pyrage import passphrase

sys.path.insert(0, "/icpc/scripts")
import icpcconfig

def make_safe_url(url: str) -> str:
    """
    Returns a parsed and quoted url
    """
    _url = urlparse(url)
    url = _url.scheme + "://" + _url.netloc + quote(_url.path) + "?" + quote(_url.query)
    return url

def fetch_url(url):
    try:
        with urllib.request.urlopen(make_safe_url(url)) as response:
            return response.read().decode("UTF-8").strip()
    except urllib.error.URLError as e:
        sg.popup(f"Exception fetching {url}:\n{e}", title="URL Fetch Error")
    except Exception as e:
        sg.popup(f"Exception fetching {url}:\n{e}", title="URL Fetch Error")
    return ''

def fetch_json(url):
    content = fetch_url(url)
    if not content:
        return None
    try:
        return json.loads(content)
    except ValueError as e:
        sg.popup(f"{url} isn't valid JSON:\n{e}", title="URL Fetch Error")
        return None

# Passphrases that worked this run; sites in a region usually share one
passphrases = []

def fetch_site_config(site_id):
    """The site's settings from contestforge, asking for the passphrase if they're encrypted.
    Returns (data, encrypted), or (None, False) if there aren't any"""
    url = f"{config_url}/{site_id}/config.json"
    config = fetch_json(url)
    if config is None:
        return None, False
    if config.get("version") != 2:
        sg.popup(f"{url} is config version {config.get('version')!r}, this image only understands version 2", title="Unsupported Config")
        return None, False
    if not config.get("encrypted"):
        return config.get("data", {}), False

    for secret in passphrases:
        try:
            return json.loads(passphrase.decrypt(config["encryptedData"].encode(), secret)), True
        except Exception:
            pass

    prompt = "This site's configuration is encrypted, enter its passphrase:"
    if config.get("note"):
        prompt += f"\n\n{config['note']}"
    while True:
        secret = sg.popup_get_text(prompt, title="Passphrase", password_char="*", keep_on_top=True)
        if secret is None:
            return None, False
        try:
            data = json.loads(passphrase.decrypt(config["encryptedData"].encode(), secret))
        except Exception:
            sg.popup("That passphrase didn't work, try again", title="Wrong Passphrase", keep_on_top=True)
            continue
        passphrases.append(secret)
        return data, True

def site_choices(tree):
    """{label: node id} for every site in a contest's tree.json, labeled by the
    names of the organizations above it"""
    sites = {}
    def walk(node, names):
        if node.get("type") == "site":
            label = " / ".join(names + [node["name"]])
            sites[label if label not in sites else f"{label} ({node['id']})"] = node["id"]
        else:
            for child in node.get("children", []):
                walk(child, names + [node["name"]])
    for child in tree.get("children", []):
        walk(child, [])
    return sites

def run_cmd(cmd, ignore_errors=False, input=None):
    p = Popen(cmd, stdin=PIPE if input is not None else None, stdout=PIPE, stderr=PIPE)
    out, err = p.communicate(input)

    if p.returncode != 0 and not ignore_errors:
        sg.popup(f"""Command: {cmd}
Code: {p.returncode}
Out:
{out}

Err:
{err}
""", title="Command Error")

    return (p.returncode, out, err)

# What a site's config may set in /icpc/config.json; everything else the image decides
SITE_SETTINGS = ["timezone", "papersize", "wallpaper_url", "autostart_firefox", "submit",
                 "reverseproxy_sites", "firefox_policies", "language_scripts", "ssh_keys"]
ADMIN_ACCOUNTS = ["icpcadmin", "teamreset"]

def set_admin_password(crypted):
    if not isinstance(crypted, str) or not re.fullmatch(r"\$6\$[^:\s]+", crypted):
        sg.popup("The site's admin password isn't a sha512-crypt hash, leaving it unchanged", title="Configuration Error")
        return
    run_cmd(["chpasswd", "-e"], input="".join(f"{a}:{crypted}\n" for a in ADMIN_ACCOUNTS).encode())

class Team(dict):
   def __str__(self):
       return f"{self['id'] : <4} {self['name'] : <30} {self['affiliation'] : <40}{' '+self['extra'] if len(self['extra']) > 0 else ''}"

class Printer(dict):
    def __str__(self):
        group = f"[{self['group']}]: " if self['group'] else ""
        return f"{group}{self['note'] if len(self['note']) > 0 else 'default'} - {self['uri']} ({self['driver']})"

# What the machine is configured with so far: build-time settings, plus the
# last setup's choices when re-running
machine_config = icpcconfig.load()

# Load list of contests from the internet
config_url = machine_config["config_url"]
configuration = {}


def mainwindow():
  # sg.theme('DarkBlue3') # this is the default anyway
  sg.theme('Default1') # this is the default anyway

  # TODO: add a button to open firefox to http://neverssl.com for captive portal activation
  # TODO: add information about how to configure wifi (click network icon top right, do the obvious thing, etc)

  # Define the layout of the window
  layout = [
    [sg.Text('ICPC Contest Setup', font=('Helvetica', 16), justification='center')],
    [sg.Text("Please answer the following questions to finalize the configuration of your environment.\nYou can re-run this setup tool later by executing '/icpc/scripts/icpc_setup -f' as root.")],
    [
      sg.Frame('Configuration Data', [
        [sg.Text('Contest', size=10), sg.Combo(["default"], size=(40,1), expand_x=True, key='contest', readonly=True, enable_events=True)],
        [sg.Text('Site', size=10), sg.Combo(["default"], size=(40,1), expand_x=True, key='site', readonly=True, enable_events=True)],
      ]),
      sg.Frame('System Options', [
        [sg.Checkbox('Autostart Firefox on login', key='autostart_firefox', default=configuration["autostart_firefox"], tooltip='This will launch Firefox on login to the desktop (i.e. when the machine boots)')],
        [sg.Checkbox('Print Test Page?', key='print_test_page', default=True)],
      ]),
      sg.Frame('Paper Size:', [
          [sg.Radio('Letter', 'PAPERSIZE', key='letter', default=configuration["papersize"] != "a4")],
          [sg.Radio('A4', 'PAPERSIZE', key='a4', default=configuration["papersize"] == "a4")]
      ], visible=False),
    ],
    [
      sg.Frame('Team Identification', [
         [sg.Text('Select your team from the list below to pre-populate the fields')],
        [sg.Listbox([], size=(60,10), font=("courier",11), key="team", horizontal_scroll=True, select_mode=sg.LISTBOX_SELECT_MODE_SINGLE, expand_x=True, enable_events=True)],
        [sg.HorizontalSeparator()],
        [sg.Text('Team Information (This is what will be used, modify if necessary)')],
        [sg.Text('Team ID', size=(10,1)), sg.InputText(key='team_id', size=(50,1))],
        [sg.Text('Team Name', size=(10,1)), sg.InputText(key='team_name', size=(50,1))],
        [sg.Text('Affiliation', size=(10,1)), sg.InputText(key='team_affiliation', size=(50,1))],
        [sg.Text('Note', size=(10,1)), sg.InputText(key='team_extra', size=(50,1))],
      ], expand_x=True)
    ],
    [
      sg.Frame('Printer configuration', [
        [sg.Column([
          [sg.Text("Select printers to install (hold ctrl to select multiple)")],
          [sg.Listbox([], size=(50,8), select_mode=sg.LISTBOX_SELECT_MODE_EXTENDED, key="configured_printers", expand_y=True, enable_events=True)],
        ]),
        sg.Column([
          [sg.Text('Enter your printer IP/hostname as a valid cups uri. E.g. ipp://10.1.2.3:631')],
          [sg.Text('Printer URI'), sg.InputText(default_text="ipp://", key='printer_uri')],
          [sg.Text('Enter the name of the driver (everywhere should be supported on all modern printers)')],
          [sg.Text('Printer Driver'), sg.InputText(default_text="everywhere", key='printer_driver')],
          [sg.Button('Add Printer', key='add_printer')],
          [sg.Text('Note: This button will add the printer to the list on the left, you need to select it in the list to actually install it', text_color='darkred')],
        ])]
      ])
    ],
    [

    ],
    [sg.Button('Refresh data from internet (will clear/reset data)', key='reload'), sg.Push(),sg.Button('Apply Configuration and Exit', key="apply")]
  ]

  # Create the window
  window = sg.Window('ICPC Contest Setup', layout, finalize=True, use_default_focus=False)
  # Trigger an event to reload the information on startup
  window.write_event_value('reload', "reload")

  # Event loop to process events and get values from inputs
  while True:

    event, values = window.read()
    # print(f"event: {event}")
    # pprint(values)

    if event == "reload":
      window['site'].update(values=["default"])
      pinned = machine_config.get("config_contest") or None
      if pinned is not None:
        contests = {pinned: pinned}
      else:
        contests = {f"{c['name']} ({c['id']})": c['id'] for c in fetch_json(f"{config_url}/contests.json") or []}
      if len(contests) == 0:
        contests = {"default": "default"}
      configuration["contests"] = contests
      first = next(iter(contests))
      window['contest'].update(values=list(contests), value=first)
      window.write_event_value('contest', first)

    if event == 'contest':
      if len(values['contest']) == 0:
        continue
      configuration["contest"] = configuration["contests"][values["contest"]]

      tree = None
      if configuration["contest"] != "default":
        tree = fetch_json(f"{config_url}/{configuration['contest']}/tree.json")
      sites = site_choices(tree) if tree else {}
      if len(sites) == 0:
        sites = {"default": "default"}
      configuration["sites"] = sites
      selected = next((label for label, id in sites.items() if id == machine_config.get("site")), next(iter(sites)))
      window['site'].update(values=list(sites), value=selected)
      window.write_event_value('site', selected)

    if event == 'site':
      if len(values['site']) == 0:
        continue

      configuration["site"] = configuration["sites"][values["site"]]
      data, encrypted = None, False
      if configuration["site"] != "default":
        data, encrypted = fetch_site_config(configuration["site"])
      configuration["data"], configuration["encrypted"] = data or {}, encrypted
      data = configuration["data"]

      if "autostart_firefox" in data:
        window['autostart_firefox'].update(bool(data["autostart_firefox"]))
      if data.get("papersize") in ("letter", "a4"):
        window[data["papersize"]].update(True)

      printers = [Printer({k: str(p.get(k) or "") for k in ("group", "uri", "driver", "note")}) for p in data.get("printers", [])]
      window['configured_printers'].update(values=printers)

      teams = [Team({k: str(t.get(k) or "").strip() for k in ("id", "name", "affiliation", "extra")}) for t in data.get("teams", [])]
      window['team'].update(values=teams)
      if len(teams) == 0:
         continue

      teamid = machine_config.get("team", {}).get("id")
      selected_idx = next((i for i, t in enumerate(teams) if t['id'] == teamid), 0)
      window['team'].update(set_to_index=selected_idx, scroll_to_index=selected_idx)
      window.write_event_value('team', [teams[selected_idx]])

    if event == 'add_printer':
      if len(values['printer_uri']) == 0:
        continue

      # Add the printer to the list
      printers = window['configured_printers'].get_list_values()
      printers.append(Printer({"group": "manual", "uri": values['printer_uri'], "driver": values["printer_driver"], "note": "Manually Added"}))
      window['configured_printers'].update(values=printers)

    if event == 'team':
      if len(values['team']) == 0:
        continue

      configuration['team'] = values['team'][0]
      window['team_id'].update(values['team'][0]['id'])
      window['team_name'].update(values['team'][0]['name'])
      window['team_affiliation'].update(values['team'][0]['affiliation'])
      window['team_extra'].update(values['team'][0]['extra'])
    if event == sg.WINDOW_CLOSED:
      break
    if event == 'apply':
      # Some basic validation:
      invalid_fields = []
      for k in ['contest', 'site', 'team_id', 'team_name', 'team_affiliation']:
        if len(values[k]) == 0:
          invalid_fields.append(k)
          continue
      # It becomes the hostname, icpc-team-<id>
      if values['team_id'] and not re.fullmatch(r"[A-Za-z0-9-]{1,53}", values['team_id']):
        invalid_fields.append('team_id (letters, digits and - only)')
      if len(invalid_fields) > 0:
        sg.popup(f"Invalid fields, please correct: {', '.join(invalid_fields)}", title="Invalid Fields")
        continue

      ret = sg.popup_yes_no(f"""
Contest: {values['contest']}
Site: {values['site']}
Team: {values['team_id']} - {values['team_name']} ({values['team_affiliation']})

Printers:
{chr(10).join([str(Printer(p)) for p in values['configured_printers']])}

Print test page: {"Yes" if values['print_test_page'] else "No"}
Autostart Firefox: {"Yes" if values['autostart_firefox'] else "No"}

Is this correct?
    """, title="Confirm Configuration")

      if ret == "Yes":
        window.close()
        return values
      else:
        continue

  window.close()


def main():
  # This script must be run as root
  # if os.geteuid() != 0:
  #     print("Error: This script must be run as root!")
  #     sys.exit(1)

  # Do some _really_ basic cli argument handling
  force = False
  if len(sys.argv) > 1 and (sys.argv[1] == "-f" or sys.argv[1] == "--force"):
      force = True

  # Exit if the configuration has already been run and the force argument was not specified
  if Path("/icpc/setup-complete").exists() and not force:
      print("Already configured. Run with -f or --force to reconfigure.")
      sys.exit(0)


  # Assume that if force wasn't specified, it's the initial boot setup, so do some extra things
  if not force:
    # Allow root to access the X server (otherwise it'll break when we change the hostname)
    run_cmd(["xhost", "+"])

    # Disable screen blanking/sleeping (just to make it easier if you're setting up lots of machines)
    run_cmd(["xset","s", "off"])
    run_cmd(["xset", "-dpms"])
    run_cmd(["xset", "s", "noblank"])

  # Figure out what contest this is, because it informs some other choices
  configuration["contest"] = machine_config.get("config_contest") or None
  configuration["autostart_firefox"] = machine_config.get("autostart_firefox", True)
  configuration["papersize"] = machine_config.get("papersize", "letter")

  values = None
  while True:
    values = mainwindow()
    print("==========================")
    pprint(values)

    if values is None or len(values['team_name']) == 0:
      continue

    break

  configuration['print_test_page'] = values['print_test_page']
  # The site's settings replace the image's whole; printers and team are picked below
  data = configuration.get("data", {})
  machine_config.update({k: data[k] for k in SITE_SETTINGS if k in data})
  machine_config.update({
      "config_contest": configuration['contest'],
      "site": configuration['site'],
      "papersize": "letter" if values['letter'] else "a4",
      "autostart_firefox": values['autostart_firefox'],
      "printers": [dict(p) for p in values['configured_printers']],
      "team": {
          "id": values['team_id'],
          "name": values['team_name'],
          "affiliation": values['team_affiliation'],
          "extra": values['team_extra'],
      },
  })
  icpcconfig.save(machine_config)

  # Never saved: config.json is readable by contestants, who could crack it.
  # An unencrypted config could have been changed on the way, so it's ignored there
  if configuration.get("encrypted") and "admin_password_hash" in data:
    set_admin_password(data["admin_password_hash"])

  (ret, out, err) = run_cmd(["/icpc/scripts/icpc-apply"], ignore_errors=True)
  if ret != 0:
      sg.popup(f"Some of the configuration couldn't be applied:\n\n{err.decode()}", title="Configuration Error")

  # Clear the screen
  print(chr(27) + "[H" + chr(27) + "[J")

  # Run the self-test script
  p = Popen("su - -c /icpc/scripts/self_test | tee /icpc/self_test_report", shell=True, stderr=PIPE)
  out, err = p.communicate()
  code = p.returncode

  if configuration["print_test_page"]:
      # remove the color codes from the self-test report so the printout isn't so ugly
      (ret, out, err) = run_cmd(["bash", "-c", "cat /icpc/self_test_report | sed -e 's/\\x1b\\[[0-9;]*m//g' | sponge /icpc/self_test_report"], ignore_errors=True)
      (ret, out, err) = run_cmd(["su", "-", "contestant", "-c", "/icpc/scripts/printfile /icpc/self_test_report"])
      print("Test page sent to printer...")

  # Remove the self-test report
  Path("/icpc/self_test_report").unlink()

  input("Press [enter] to continue")
  Path("/icpc/setup-complete").write_text(configuration["site"] + "\n")

  # Logout so we can continue with booting (but only if run without force)
  if not force:
    run_cmd(["xfce4-session-logout", "--logout"])




if __name__ == "__main__":
    main()
