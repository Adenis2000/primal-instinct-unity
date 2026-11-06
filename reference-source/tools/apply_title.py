#!/usr/bin/env python3
"""Syncs the game's name from data/game.json into the files Godot reads before any script runs:
project.godot (project / window name), export_presets.cfg (preset names, output file names, product name) and the README
(heading, run table). Run after editing data/game.json, then re-export. Usage: tools/apply_title.py"""
import json, re, os
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
g = json.load(open(os.path.join(root, "data", "game.json")))
title, slug, zslug = g["title"], g["slug"], g["zip_slug"]

def edit(path, fn):
    p = os.path.join(root, path)
    s = open(p, encoding="utf-8").read()
    n = fn(s)
    if n != s:
        open(p, "w", encoding="utf-8").write(n)
        print("updated", path)

def proj(s):
    s = re.sub(r'^config/name=.*$', 'config/name="%s"' % title, s, flags=re.M)
    if re.search(r'^config/version=', s, flags=re.M):
        s = re.sub(r'^config/version=.*$', 'config/version="%s"' % g.get("version", "0.1.0"), s, flags=re.M)
    else:
        s = re.sub(r'^(config/name=.*)$', r'\1\nconfig/version="%s"' % g.get("version", "0.1.0"), s, count=1, flags=re.M)
    return s
edit("project.godot", proj)

def presets(s):
    s = re.sub(r'^name="[^"]*Linux"$', 'name="%s - Linux"' % title, s, flags=re.M)
    s = re.sub(r'^name="[^"]*Web"$', 'name="%s - Web"' % title, s, flags=re.M)
    s = re.sub(r'^name="[^"]*Windows Desktop"$', 'name="%s - Windows"' % title, s, flags=re.M)
    s = re.sub(r'export_path="builds/linux/[^"]*"', 'export_path="builds/linux/%s.x86_64"' % slug, s)
    s = re.sub(r'export_path="builds/windows/[^"]*"', 'export_path="builds/windows/%s.exe"' % slug, s)
    s = re.sub(r'application/product_name="[^"]*"', 'application/product_name="%s"' % title, s)
    s = re.sub(r'application/file_description="[^"]*"', 'application/file_description="%s"' % title, s)
    return s
edit("export_presets.cfg", presets)

def readme(s):
    s = re.sub(r'^# .* \(working title\)', '# %s (working title)' % title, s, count=1, flags=re.M)
    s = re.sub(r'`unzip [^`]*`', '`unzip %s-linux-x86_64.zip && ./%s.x86_64`' % (zslug, slug), s)
    s = re.sub(r'`\./\w+\.x86_64 --headless -- --selftest`', '`./%s.x86_64 --headless -- --selftest`' % slug, s)
    s = re.sub(r'app_userdata/[^/]*/settings\.cfg', 'app_userdata/%s/settings.cfg' % title, s)
    s = re.sub(r'app_userdata\\[^\\]*\\settings\.cfg', lambda m: 'app_userdata\\%s\\settings.cfg' % title, s)
    return s
edit("README.md", readme)
