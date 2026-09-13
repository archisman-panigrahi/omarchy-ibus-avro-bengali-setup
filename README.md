# IBus Avro (Bangla/Bengali) on Omarchy

Bangla typing is broken out of the box on Omarchy/Hyprland (fcitx env overrides,
ibús never autostarts, and the GTK panel steals focus while typing).

Run this script to install and configure IBus + Avro properly:

```bash
git clone github.com/archisman-panigrahi/omarchy-ibus-avro-setup
cd omarchy-ibus-avro-setup
bash setup-ibus-avro.sh
```

After it finishes, log out and back in, then toggle Bangla with **Ctrl+Space**.

For a breakdown of how the script works and why the problem exists, see [`details.md`](details.md).

This setup also works for other IBus engines/languages — see [`other-engines.md`](other-engines.md).
