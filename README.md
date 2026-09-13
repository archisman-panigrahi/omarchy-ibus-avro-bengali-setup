# IBus Avro (Bengali) on Omarchy

Bengali typing is broken out of the box on Omarchy/Hyprland (fcitx env overrides,
ibús never autostarts, and the old GTK panel steals focus while typing).

Run this script to install and configure IBus + Avro properly:

```bash
bash setup-ibus-avro.sh
```

After it finishes, log out and back in, then toggle Bengali with **Ctrl+Space**.

For a breakdown of how the script works and why the problem exists, see [`details.md`](details.md).