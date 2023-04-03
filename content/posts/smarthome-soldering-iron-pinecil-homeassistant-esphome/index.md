---
title: 'Smarthome Soldering Iron with Home Assistant and ESPHome (also: web GUIs for Pinecil)'
description: 'Learn how to create a smart soldering iron using Pinecil with Home Assistant and ESPHome, as well as explore the options for controlling and monitoring your Pinecil with Bluetooth'
date: 2023-03-28T19:01:25-04:00
draft: false
categories: [Home Automation, DIY, FOSS]
tags: [Pinecil, Home Assistant, DIY, RISC-V, Blisp, PineSAM, Pine64, esphome]
---

About a year ago, [wesdottoday](https://hachyderm.io/@wesdottoday) told me to
buy a Pinecil and, once they came back in stock before the holidays.. I did just
that... Fast forward a couple months and I've got a
[copr](https://copr.fedorainfracloud.org/coprs/neil/blisp/) for flashing the
Pinecil's firmware (IronOS), and am spending my weekends playing around with
Bluetooth Low Energy (BLE) and Home Assistant to automatically turn on my fan
when I start tinkering at my desk, lest my lungs die from the fumes.

<p>

{{< figure src="pinecil-esp32.jpg" alt="ESP-WROOM-32 Development MCU with a Pinecil v2 leaning on it" class="inline-40 left" >}}

By popular demand, I'm writing a blog post about the Pinecil, how to flash the
latest firmware, and then what you can (currently) do with bidirectional
communication to your soldering iron.
</p>

We'll also go over two Pinecil community projects offering in-browser
experiences (PineSam and Joric's 'Pinecil'), and lastly some instructions on
using an [ESP32](https://www.espressif.com/en/products/socs/esp32) and
[ESPHome](https://esphome.io/) to send Pinecil data to
[HomeAssistant](https://home-assistant.io/) so you can do everything from
visualize your soldering statistics, to automatically turn on an exhaust fan
when you start working.

## The Pinecil

The [Pinecil](https://www.pine64.org/pinecil/) is an open-source soldering iron
based on the RISC-V architecture produced by Pine64. There are two versions of
Pinecil - v1 and v2. Pinecil v1 does not have a Bluetooth Low Energy (BLE) chip,
whereas Pinecil v2 does. In this blog post, we will focus on Pinecil v2. Pine64
does not distinguish between v1 and v2 except for on the PCB as a revision. If
you're buying a Pinecil in 2023 or beyond, and it's from an official source, it
is a v2.

You can find more information about the Pinecil in the links below, including
where to buy. Check the Pinecil Wiki for up-to-date information on where to buy
a genuine Pinecil, and how to avoid fakes.

### Links

- [Pine64.com](https://pine64.com/) - Offical store for Pine64 devices. Ships
  from China and takes 3-4 weeks for delivery
- [Pine64.org](https://pine64.org) - The community associated with Pine64
  devices. Check out the Discord/Telegram chat for a great group of tinkerers,
  and if you have any trouble with your Pinecil or associated tools
- [Pinecil Wiki](https://wiki.pine64.org/wiki/Pinecil) - Lots of tips and
  tricks, as well as up to date purchasing and troubleshooting information.
  - Shout out to River-Mochi for their _awesome_ work on keeping this up to date
    and useful

## Blisp

Blisp is a flashing tool used to flash ironOS on Pinecil v2 that stands for
'Bouffalo Labs In-System Programming'. It's used to flash the Bouffalo BL706 MCU
that was integrated on the v2 Pinecil. You can find the source code for Blisp on
[GitHub](https://github.com/pine64/blisp).

I also maintain a Fedora COPR respository for it
[here](https://copr.fedorainfracloud.org/coprs/neil/blisp/), where you can find
packages with precompiled binaries for Fedora and Enterprise Linux (8/9). I am
working with Pine64 to make it easier to get it packaged for Fedora and other
Linux distributions down the road.

### Flashing the beta firmware with blisp

Until version v2.21 of IronOS ships, a beta firmware is required to use the BLE
functionality of the Pinecil v2. There has been a significant amount of testing
and development on the BLE stack on the main tree in the last few months and the
developers have been making sure the BLE features are ready before they are
released to a much larger audience.

{{< figure src="blisp-flash.png" alt="Flashing the Pinecilv2 with blisp CLI" class="" >}}

Once v2.21 is released, binaries can be retrieved from the
[IronOS Releases](https://github.com/Ralim/IronOS/releases) page.

#### Steps to download and flash

These steps assume you have a compiled version of `blisp` in your system path,
either by installing from my COPR, or compiling on your own using the
instructions in the repository.

1. Find the latest sucessful actions run on the ironos repo
   [here](https://github.com/Ralim/IronOS/actions/workflows/push.yml?query=branch%3Adev+event%3Apush).
2. Download the `Pinecilv2_multi-lang` binary for that run, and unzip it
3. Plug your Pinecil into your computer while holding down the 'Minus' (-)
   button. The screen should **not** turn on. If on Linux, `dmesg` should report
   seeing the BL706 as a serial device.
4. Run the following command to flash the firmware to your Pinecil:
   ```
   blisp write -c bl70x --reset /path/to/Pinecilv2_multi-lang/Pinecilv2_EN.bin
   ```
5. Un-plug and plug the Pinecil back in to boot the new firmware

### Pineflash

[Spagett1](https://github.com/Spagett1) updated their Pineflash tool which allows
for a non-command-line experience for flashing new versions of IronOS on the Pinecil V1 and V2, similar to the Pine64 updater (add link) utility for the v1 Pinecil. You can find
more information on the PineFlash
[GitHub repo](https://github.com/Spagett1/PineFlash). Feel free to check it out
and give them feedback!

## Bluetooth Low Energy

Bluetooth Low Energy (BLE) is a wireless communication protocol that is designed
to consume less energy than classic Bluetooth. There is upcoming support in
browser APIs to allow access to BLE devices, and so there are a handful of
options for how to get your Pinecil talking to your computer.

## Interacting with your Pinecil over Bluetooth

### PineSAM (Pinecil Settings and Menus) by [Builder555](https://github.com/builder555)

PineSAM (Pinecil Settings and Menus) started out as an in-browser way to see and
change settings. It's served a multitude of uses from helping people with
cracked or non-functional screens, all the way to adding really helpful
accessibility features to those who struggle to read the small screen on the
Pinecil. It's is a Python and Vue-based application that has to have a server
component running locally--along with a machine that has bluetooth. You can find
the source code for PineSAM on [GitHub](https://github.com/builder555/PineSAM/).

{{< figure src="pinesam.png" alt="PineSAM UI" class="inline" >}}

PineSAM allows the user to not only see the live temperature, wattage, and
voltage of their device but change the settings and temperatures at a click.
Uniquely, it allows users to set temperature presets for one-click changes
between temperatures--for example to switch between leaded and unleaded solder.

{{< figure src="pinesam-mobile.png" alt="Screenshot of PineSAM UI on Mobile device" class="inline-40 left" >}}

The PineSAM project is working to integrate a "Work" screen which takes
inspiration from Joric's UI. Due to this, it's likely these two projects will
end up combining into one, in my opinion, despite their distinct mechanisms for
retrieving BLE data from the Pinecil.

#### Setting up PineSAM

See the
[project readme](https://github.com/builder555/PineSAM#i-using-pre-made-binaries)
for the most up-to-date instructions. If you run into any trouble, come find us
in the #pinecil channel on Pine64's Discord or Telegram chat.

### [Joric](https://github.com/joric/)'s BLE API

Another project is a more simple web UI that uses in-browser Bluetooth support
(currently only really well supported in Chromium/Firefox, and even then it's
not universal or without bugs. This UI shows a nice graph of your Pinecil's
temperature and power supply information, but is limited to devices supporting
WebBLE, and also is only able to change the set point (temperature) on the
device. You can also find the source code for Joric UI on
[GitHub](https://github.com/joric/pinecil).

{{< figure src="joric-ui.png" alt="Joric's UI" class="inline-60 right" >}}

#### Setting up Joric's UI

No setup needed! Just browse to
[https://joric.github.io/pinecil/](https://joric.github.io/pinecil/) in a
compatible browser. I've personally tested Firefox and Chromium on Fedora 37,
but I know others have got it working on Windows and MacOS, too.

As with PineSAM, feel free to come to chat for help and support.

## Home Assistant Setup with ESPHome

If Home Assistant (HASS) is more your speed, read on below. Be warned to get
this setup, you will need some sort of ESP32 device to read data from your
Pinecil and report it to Home Assistant. I used one of the
[WROOM ESP32 dev boards](https://www.amazon.com/ESP-WROOM-32-Development-Microcontroller-Integrated-Compatible/dp/B08D5ZD528)
I've had in my closet for a few months (not an affiliate link).

If you're not familiar, Home Assistant is an open-source home automation
platform which can inte grate with ESPHome, another open source system to
control your ESP8266/ESP32 using just YAML configurations. In this section, I'll
walk though how to setup an ESP32 with will show you how to create a smart
soldering iron using Pinecil with Home Assistant and ESPHome.

{{< figure src="hass-soldering.png" alt="Home Assistant Soldering UI" class="inline" >}}

To make this work, we'll use an
[ESPHome configuration file](https://github.com/TomW1605/esphome_pinecilv2_ble/blob/main/esphome_pinecilv2_ble.yaml)
put together by Pine64 community member TomW1605. Thank you again, Tom!

## Requirements

- ESP32 device (Non affiliate link:
  [ESP-WROOM-32 Development MCU on Amazon](https://www.amazon.com/ESP-WROOM-32-Development-Microcontroller-Integrated-Compatible/dp/B08D5ZD528))
- Home Assistant already setup
- ESPHome already setup

## Steps

1. Login to ESPHome
2. Import
   [this ESPHome configuration file](https://github.com/TomW1605/esphome_pinecilv2_ble/blob/main/esphome_pinecilv2_ble.yaml).
3. Modify and set up the configuration file as follows:
   1. Change board in esp32 section to your board.
      - If using the WROOM 32 I linked above, use `nodemcu-32s`
   2. Setup an encryption key. This must be a base64-encoded, 32 bit string.
      - You can create one on the CLI using `openssl rand -base64 32`
   3. Change OTA password to desired
   4. Change wifi SSID and password for your network in ESPHome secrets
   5. Change wifi access point fallback settings to desired
   6. **Important** - Change ble_client mac address to your Pinecil's MAC. This
      can be found in the settings as well as in logs from the above tools
      (Joric/PineSAM)
   {{< figure src="pinecil-esphome.png" alt="Pinecil esp32 configuration example" class="inline" >}}
4. Flash the firmware to the ESP32 device
5. Add the device to Home Assistant
6. Create a Home Assistant dashboard to control and monitor your smart soldering
   iron.
   - An example dashboard can be found at
     https://gist.github.com/NeilHanlon/83d6e2cdc6eb83cb205b617f80c2a7c3
   - It uses the 'mini-graph-card' and 'auto-entities' integrations from HACS
  {{< gist neilhanlon 83d6e2cdc6eb83cb205b617f80c2a7c3 >}}

Now that you've got that setup, you should start to see data coming in about
your Pinecil's settings! Go on and automate thy solder.
