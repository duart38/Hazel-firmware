# Hazel for the X1D-50c

Film looks in the live view of a Hasselblad X1D-50c (the first model, firmware 1.25.0). What
you see in the viewfinder is the look the photo gets, and each photo gets a small `.look` file
next to it saying which recipe it was taken with. The raw files themselves are never changed.

Everything goes over the camera's USB connection to a Mac. Nothing is opened, nothing is
flashed, and no firmware is replaced. Take the memory card out and the camera starts as it
always did.

> Not made by, endorsed by or affiliated with Hasselblad. You run this on your own camera at your
> own risk. It was built and tested on one camera.
>
> Written with Claude (Anthropic's AI assistant) and checked on a real camera.

## What's here

- `catkin`, `camera/`, `usb/`: **Catkin**, the loader. Installed once, it runs a setup from the
  memory card every time the camera starts.
- `hazel/`: **the film look**, ready-built: the setup Catkin loads from the card, with seven
  recipes in its slots.

## What it changes on the camera

| Where | What | Stays after a restart? |
| --- | --- | --- |
| system partition, `/etc/systemd/system/` | `x1d-card-loader.service`, and a link to it | yes, until a firmware update |
| data partition, `/media/data/x1d-card-loader/` | the loader script and its key | yes |
| data partition, `/media/data/x1d/` | the slot and look you picked last, and debug logs if you switch them on | yes |
| memory only (`/tmp`, `/run`) | the film look itself | no |

The service is the only change to the camera's own software, and a firmware update removes it.

## You need

A Mac, the camera with firmware 1.25.0, its USB-C cable, Python 3 and libusb:

```bash
brew install libusb
```

```bash
python3 -m venv .venv && .venv/bin/pip install pyusb
```

## 1. Put the loader on the camera

Switch the camera on, connect it to the Mac, then:

```bash
.venv/bin/python catkin install
```

It shows exactly what it will change and asks you to type `install` before doing it. It also
makes a key on your Mac (`~/.config/catkin/key`) and puts a copy on the camera. The camera only
runs a card setup sealed with that key, so a stranger's card can't run anything on it. Keep the
key private and back it up.

`.venv/bin/python catkin status` shows what's installed at any time.

## 2. Prepare the memory card

Seal the film look with your key:

```bash
.venv/bin/python catkin pack hazel
```

Then copy it onto the card, either with the card in a card reader:

```bash
.venv/bin/python catkin card --to /Volumes/CARD
```

or with the card in the camera:

```bash
.venv/bin/python catkin card --usb
```

This puts `CATKIN.TAR` and `CATKIN.SIG` at the top of the card. Restart the camera with the card
in. Within about half a minute of switching on, the look is on.

To check it first without restarting, run `.venv/bin/python catkin try`. It loads the card's
setup right away and prints what happened.

## Using it

On the camera: **Settings › Extras**. Switch the film look on or off, and pick one of the seven
recipe slots.

To use other recipes, put text files named `C1.txt` to `C7.txt` in a `HAZEL/recipes` folder on
the card (at most 2 KB each). The camera reads them when it starts and when you open the menu.
There are recipes to start from in
[Hazel-film-recipes](https://github.com/duart38/Hazel-film-recipes). Without that folder, the
camera uses the seven recipes in `hazel/slots`.

Formatting the card in the camera removes the setup, like everything else on the card.

## Undo

- **Back to stock for one start:** take the card out, or delete `CATKIN.TAR` from it.
- **Remove the loader:** `.venv/bin/python catkin remove` deletes the service and
  `/media/data/x1d-card-loader`. The few bytes of settings in `/media/data/x1d` stay; without the
  loader nothing reads them.
- A firmware update also removes the service.

## Credits

The USB tools in `usb/` come from
[YuHaoyua/hasselblad-x1d-reverse-engineering](https://github.com/YuHaoyua/hasselblad-x1d-reverse-engineering)
(MIT licence, see `usb/LICENSE`).
