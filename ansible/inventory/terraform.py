#!/usr/bin/env python3
"""Dynamic inventory from OpenTofu outputs. Run: ./terraform.py --list"""
import json, os, subprocess, sys


def outputs():
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    r = subprocess.run(["tofu", "output", "-json"], capture_output=True, text=True, cwd=root)
    if r.returncode != 0 or not r.stdout.strip():
        return {}
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return {}


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--list":
        o = outputs()
        ips = o.get("server_ip", {}).get("value", {})
        fqdns = o.get("fqdn", {}).get("value", {})
        devs = o.get("data_volume_device", {}).get("value", {})
        common = {
            "lab_username": o.get("lab_username", {}).get("value", "lab"),
            "base_domain": o.get("base_domain", {}).get("value", "example.com"),
            "wg_server_address": o.get("wg_server_address", {}).get("value", "10.99.0.1/24"),
            "wg_peer_address": o.get("wg_peer_address", {}).get("value", "10.99.0.2/32"),
            "wg_peer_public_key": o.get("wg_peer_public_key", {}).get("value", ""),
            "wg_listen_port": o.get("wg_listen_port", {}).get("value", 51820),
            "kali_gui": o.get("kali_gui", {}).get("value", "xfce"),
            "kali_toolset": o.get("kali_toolset", {}).get("value", "default"),
            "kali_mullvad": o.get("kali_mullvad", {}).get("value", False),
        }
        inv = {"kali": {"hosts": list(ips.keys())},
               "_meta": {"hostvars": {}}}
        for name, ip in ips.items():
            hv = dict(common)
            hv.update({"ansible_host": ip, "fqdn": fqdns.get(name, ""),
                       "data_volume_device": devs.get(name, "")})
            inv["_meta"]["hostvars"][name] = hv
        print(json.dumps(inv))
    elif len(sys.argv) == 3 and sys.argv[1] == "--host":
        print(json.dumps({}))
    else:
        sys.exit("usage: terraform.py --list | --host <name>")


if __name__ == "__main__":
    main()
