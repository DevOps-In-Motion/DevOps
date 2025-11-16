
# Homelab overview

These are general instructions to setup a simple homelab. The tutorial is based on an architecture from reddit.

## Notes

Make sure your router from your ISP can support VLANs. Check by accessing the routers management console and check in the settings. Or, google it, lol. If you're like me an do not have a router that supports VLANs then there is another solution.

## Installation instructions


Flash to disk

```bash
# write opnsense to disk for installation
sudo dd if=OPNsense-##.#.##-[Type]-[Architecture].[img|iso] of=/dev/rdiskX bs=64k`

```


