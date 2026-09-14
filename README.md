# IBus Avro (Bangla/Bengali input method) on Omarchy

## Here is how to type Bengali (Bangla) in Omarchy Linux using the Avro phonetic keyboard.

This guide explains how to set up IBus Avro on Omarchy, the Arch/Hyprland-based Linux distribution. The usual IBus/Avro installation instructions do not work out of the box on Omarchy because Omarchy uses Fcitx5 by default and has environment settings that interfere with IBus.

Run this script to install and properly configure [ibus-avro](https://github.com/sarim/ibus-avro/):

```bash
git clone github.com/archisman-panigrahi/omarchy-ibus-avro-setup
cd omarchy-ibus-avro-setup
bash setup-ibus-avro.sh
```

After it finishes, log out and back in, then toggle Bangla with **Ctrl+Space**.

For a breakdown of how the script works and why the problem exists, see [`details.md`](details.md).

This setup also works for other IBus engines/languages — see [`other-engines.md`](other-engines.md).

If you want to use fcitx5 instead of iBus, then please head over to [this repo](https://github.com/Xinthian/omarchy-bangla-input).
