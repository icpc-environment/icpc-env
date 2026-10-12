#!/icpc/scripts/venv/bin/python
import FreeSimpleGUI as sg
from pathlib import Path
import urllib.request
from urllib.parse import urlparse, quote
from subprocess import PIPE, Popen
import sys
import csv
import os
from pprint import pprint

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

def run_cmd(cmd, ignore_errors=False):
    p = Popen(cmd, stdout=PIPE, stderr=PIPE)
    out, err = p.communicate()

    if p.returncode != 0 and not ignore_errors:
        sg.popup(f"""Command: {cmd}
Code: {p.returncode}
Out:
{out}

Err:
{err}
""", title="Command Error")

    return (p.returncode, out, err)

class Team(dict):
   def __str__(self):
       return f"{self['id'] : <4} {self['name'] : <30} {self['affiliation'] : <40}{' '+self['extra'] if len(self['extra']) > 0 else ''}"

class Printer(dict):
    def __str__(self):
        return f"[{self['group']}]: {self['note'] if len(self['note']) > 0 else 'default'} - {self['uri']} ({self['driver']})"

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
      configuration["contest"] = machine_config.get("contest") or None
      contest_list = [configuration["contest"]]
      if configuration["contest"] is None:
        contest_list = fetch_url(f"{config_url}/contests").splitlines()

      if len(contest_list) == 0:
         contest_list = ["default"]
      window['contest'].update(values=contest_list, value=contest_list[0])
      window.write_event_value('contest', contest_list[0])

    if event == 'contest':
      if len(values['contest']) == 0:
        continue
      configuration["contest"] = values["contest"]
      configuration["site"] = machine_config.get("site")
      configuration['url'] = config_url + '/' + configuration['contest']


      content = fetch_url(f"{config_url}/{values['contest']}/sites.csv")
      sites = list(csv.DictReader(content.splitlines(), fieldnames=["id", "name"]))
      if len(sites) == 0:
         window['site'].update(values=["default"])
         window.write_event_value('site', "default")
      else:
        site_values = [f"{s['id']}: {s['name']}" for s in sites]
        selected = site_values[0]
        if configuration["site"] is not None:
          selected = next((s for s in site_values if s.startswith(configuration["site"])), site_values[0])
        window['site'].update(values=site_values, value=selected)
        window.write_event_value('site', selected)

    if event == 'site':
      if len(values['site']) == 0:
        continue

      configuration["site"] = values["site"].split(":")[0]

      teamid = machine_config.get("team", {}).get("id")

      # Update the list of teams when the site changes
      content = fetch_url(configuration['url'] + f"/teams/{configuration['site']}_teams.csv")
      teams = list(csv.DictReader(content.splitlines(), fieldnames=["id", "name", "affiliation", "extra"]))
      teams = list(map(lambda t: {k: v.strip() for k, v in t.items()}, teams))
      if len(teams) == 0:
         continue

      selected_idx = 0
      if teamid is not None:
        selected_idx = next((i for i, t in enumerate(teams) if t['id'] == teamid), 0)

      window['team'].update(values=[Team(t) for t in teams], set_to_index=selected_idx, scroll_to_index=selected_idx)
      window.write_event_value('team', [Team(teams[selected_idx])])

      # Update the printers when the site changes:
      content = fetch_url(configuration['url'] + f"/printers/{configuration['site']}_printers2.csv")
      printers = list(
          csv.DictReader(
              content.splitlines(), fieldnames=["group","uri", "driver", "note"], restval="Automatically Provisioned"
          )
      )
      window['configured_printers'].update(values=[Printer(p) for p in printers])

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
  configuration["contest"] = machine_config.get("contest") or None
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
  machine_config.update({
      "contest": values['contest'],
      "site": values['site'].split(":")[0],
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
