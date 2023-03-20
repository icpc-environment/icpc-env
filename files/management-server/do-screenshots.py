#!/usr/bin/env python3
import os
import os.path
import sys
import re
import subprocess
from datetime import datetime
import multiprocessing as mp
from collections import defaultdict
import pathlib
from pprint import pprint


home = os.environ['HOME']
SCREENSHOT_DIR = f'/srv/contestweb/screens'
TIMESTAMP = datetime.now().strftime("%Y%m%d-%H_%M_%S")

SITELIMIT = sys.argv[1] if len(sys.argv) > 1 else None


class Host:
  def __init__(self, host, site):
    self.host = host
    self.site = site
    self.filename = f"{TIMESTAMP}.png"
    self.screenshot_dir = f"{SCREENSHOT_DIR}/{self.site}/{self.host}"
    self.thumbnail_dir = f"{self.screenshot_dir}/thumbs"

    # actual files
    self.screenshot = None
    self.thumbnail = None

  def screenshot_url(self):
    return self.screenshot[len(f"{SCREENSHOT_DIR}/"):]
  def thumbnail_url(self):
    return self.thumbnail[len(f"{SCREENSHOT_DIR}/"):]

  def take_screenshot(self):
    pathlib.Path(self.screenshot_dir).mkdir(parents=True, exist_ok=True)

    cmd = f'timeout 10 ssh {self.host} sudo -u contestant env DISPLAY=:0 import -window root png:- > {self.screenshot_dir}/{self.filename}'
    try:
      out = subprocess.run(cmd, shell=True, check=True, capture_output=True)
      print(f'Screenshot taken of {self.host}')
      self.screenshot = f"{self.screenshot_dir}/{self.filename}"
    except subprocess.CalledProcessError as e:
      print(f'Failed to screenshot {self.host}')
      print(e)
      print('============================')
      os.remove(f'{self.screenshot_dir}/{self.filename}')

  def create_thumbnail(self):
    print(f"checking thumbnail for {self.host}")
    # Nothing to do if there's no screenshot
    if self.screenshot is None:
      return

    # Make sure the directory exists
    pathlib.Path(self.thumbnail_dir).mkdir(parents=True, exist_ok=True)

    # otherwise, make a thumbnail
    print(f'Thumbnailing {self.host}')
    cmd = f"cd {self.screenshot_dir} && mogrify -format png -path thumbs -thumbnail 320x {self.filename}"
    out = subprocess.run(cmd, shell=True, capture_output=True)
    if out.returncode != 0:
      print(out)
    self.thumbnail = f"{self.thumbnail_dir}/{self.filename}"

def screenshot_wrapper(h):
  h.take_screenshot()
  return h
def thumbnail_wrapper(h):
  h.create_thumbnail()
  return h

def main():
  now = datetime.now()

  with open(f'{home}/icpcnet_hosts', 'r') as f:
    hostlines = f.readlines()
    hostlines = [line.strip() for line in hostlines
                 if not line.startswith('#') and line.strip() != '']
    hosts = []
    for line in hostlines:
      hostnames = line.split('#')[0].split()[1:]
      hosts.extend(hostnames)

  # grab full hostnames, so we have site information
  r = re.compile(r"[^.]+\.[^.]+\.icpcnet\.internal")
  hosts = list(filter(r.match, hosts))
  hosts = list(map(lambda h: Host(*h.split('.')[:2]), hosts))

  hosts = list(filter(lambda h: SITELIMIT is None or SITELIMIT == h.site, hosts))

  # fetch 24 screenshots at a time
  pool = mp.Pool(processes=24)
  hosts = pool.map(screenshot_wrapper, hosts)
  pool = mp.Pool(processes=4)
  hosts = pool.map(thumbnail_wrapper, hosts)

  site_hosts = defaultdict(list)
  for h in hosts:
    site_hosts[h.site].append(h)

  # site content generation
  site_html = defaultdict(str)
  for site,hosts in site_hosts.items():
    for h in sorted(hosts, key=lambda h: h.host):
      if h.screenshot is None:
        site_html[site] += f'<div class="col-lg-4 col-md-4 col-sm-4 col-xs-6">{h.host}<br><img src="https://via.placeholder.com/480x270" style="width: 100%;"></div>\n'
      else:
        site_html[site] += f'<div class="col-lg-4 col-md-4 col-sm-4 col-xs-6">{h.host}<br><img class="lightbox" data-original="{h.screenshot_url()}" src="{h.thumbnail_url()}" style="width: 100%;"></div>\n'
    site_html[site] += f'</div>'

  header = f'''<!doctype html>
  <html lang="en">
    <head>
      <!-- Required meta tags -->
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">

      <!-- Bootstrap CSS -->
      <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-1BmE4kWBq78iYhFldvKuhfTAU6auU8tT94WrHftjDbrCEXSU1oBoqyl2QvZ6jIW3" crossorigin="anonymous">
      <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/basiclightbox@5.0.4/dist/basicLightbox.min.css" integrity="sha256-r7Neol40GubQBzMKAJovEaXbl9FClnADCrIMPljlx3E=" crossorigin="anonymous">
      <title>Screenshots {TIMESTAMP}!</title>
<style>
{".basicLightbox__placeholder { pointer-events: none !important; }"}
</style>
    </head>
    <body>
      <div class="container">
        <div class="row">
          <div class="col-md-12"><h2>{TIMESTAMP}</h2></div>
        </div>
  '''

  footer = '''
      </div>
      <!-- Optional JavaScript; choose one of the two! -->

      <!-- Option 1: Bootstrap Bundle with Popper -->
      <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js" integrity="sha384-ka7Sk0Gln4gmtz2MlQnikT1wXgYsOg+OMhuP+IlRH9sENBO0LRn5q+8nbTov4+1p" crossorigin="anonymous"></script>
      <script src="https://cdn.jsdelivr.net/npm/basiclightbox@5.0.4/dist/basicLightbox.min.js" integrity="sha256-nMn34BfOxpKD0GwV5nZMwdS4e8SI8Ekz+G7dLeGE4XY=" crossorigin="anonymous"></script>
      <script>
      document.querySelectorAll('img.lightbox').forEach((img) => {
        const elem = `<div style='pointer-events: none; width:90vw; height:90vh; background-size:contain; background-repeat: no-repeat; background-image:url("${img.dataset.original}")'></div>`
        const instance = basicLightbox.create(elem);
        img.onclick = instance.show;
      })
      </script>

      <!-- Option 2: Separate Popper and Bootstrap JS -->
      <!--
      <script src="https://cdn.jsdelivr.net/npm/@popperjs/core@2.10.2/dist/umd/popper.min.js" integrity="sha384-7+zCNj/IqJ95wo16oMtfsKbZ9ccEh31eOz1HGyDuCQ6wgnyJNSYdrPa03rtR1zdB" crossorigin="anonymous"></script>
      <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.min.js" integrity="sha384-QJHtvGhmr9XOIpI6YVutG+2QOK9T+ZnN4kzFN1RtK3zEFEIsxhlmWl5/YESvpZ13" crossorigin="anonymous"></script>
      -->
    </body>
  </html>
    '''

  # Only write the index.html if there's not a sitelimit in place
  if SITELIMIT is None:
    with open(f'{SCREENSHOT_DIR}/index.html', 'w') as html:
      html.write(header)
      html.write(f'<div class="row"><div class="col-md-12"><ul>')
      for site,html_content in site_html.items():
        html.write(f'<li><a href="{site}.html">{site}</a></li>')
      html.write(f'</ul></div></div>')

      for site,html_content in site_html.items():
        html.write(f'<div class="row"><div class="col-md-12"><h2><a href="{site}.html">{site}</a></h2></div>')
        html.write(html_content)
      html.write(footer)

  # make individual site pages
  for site,html_content in site_html.items():
    with open(f'{SCREENSHOT_DIR}/{site}.html', 'w') as html:
      html.write(header)
      html.write(f'<div class="row"><div class="col-md-12"><h2>{site}</h2></div>')
      html.write(html_content)
      html.write(footer)

if __name__ == '__main__':
    main()
