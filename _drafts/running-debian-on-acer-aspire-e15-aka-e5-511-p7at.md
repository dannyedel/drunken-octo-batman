---
title: "Running Debian Jessie on an Acer Aspire E15 (aka E5-511-P7AT)"
---

The good news first: The Laptop *can* work with debian jessie, but not (yet)
out of the box. While you can use most of the device straight away, you will
need to do some tweaking for the graphics card, wireless network, and
bluetooth. This post explains how I got it to work.

* Table of contents
{:toc}

## tl,dr: Summary

* Wait how [Debian bug #778604][deb778604] plays out
before you connect an external monitor, or upgrade your kernel to v3.19+.
* If you *do* upgrade your kernel to v3.19+, be prepared to patch the
broadcom-sta (wireless lan) package with the patches from
[debian bug #773713][deb773713]
* Bluetooth requires a binary blob from the windows driver and kernel-patching.
If you want bluetooth, get a coffee (and read the long version).

---

## Graphics card (i915, Bay Trail, ValleyView, 8086:0f31 - 1025:0905)

lspci -nnk:

```
00:02.0 VGA compatible controller [0300]: Intel Corporation Atom Processor Z36xxx/Z37xxx Series Graphics & Display [8086:0f31] (rev 0e)
	Subsystem: Acer Incorporated [ALI] Device [1025:0905]
	Kernel driver in use: i915
```

Symptom: When connecting an external monitor (via HDMI or VGA)
the X server freezes.

This is a bug in the i915 driver -- connecting an external screen
results in a lockup, duplicating the (previously internal) contents
on the external screen and ignoring mouse and keyboard input:

![screen locking up example](/assets/images/acer-screen-lockup.jpg)

You can still CTRL+ALT+F1, login as root and issue `service gdm restart`
(with the HDMI cable disconnected), but it may take a bit until it
actually restarts.

### Known workaround:
This issue is fixed in the newest kernels.

Install a linux kernel >= 3.19, for example from
[debian snapshots' kernel images][snapshotlinux] or build one from
source:

```
git clone git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
cd linux
cp /boot/config-$(uname -r) .config
make olddefconfig
fakeroot make deb-pkg
```

I have [reported this issue][deb778604] to the debian bugtracker,
hoping to backport the driver to jessie.

For reference: According to my testing, this issue was fixed in
[commit 83b8459][git83b8459]

### Work left to do:

Figure out if it's possible to backport the i915 driver to jessie's kernel.
Look at [debian bug 778604][deb778604] for status on that.

[snapshotlinux]: http://snapshot.debian.org/package/linux/
[deb778604]: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=778604
[git83b8459]: http://git.kernel.org/cgit/linux/kernel/git/stable/linux-stable.git/commit/?id=83b8459756659ce55446e3eb97d64b966c60bfb9

---

## Wireless LAN

lspci:

```
FIXME lspci
```

The Acer comes with a Broadcom BCM43142 combined WLAN+Bluetooth
chipset. Note that it is *not* (yet?) supported by the open-source
drivers and needs the broadcom binary driver (`wl`) to work.
Install the [broadcom-sta-dkms] package from `non-free` to get the `wl`
kernel module.

*Little problem:* broadcom-sta-dkms (at least version `6.30.223.248-3`) does not build
correctly on 3.18+ kernels (Which I was using because of the `i915`
issue above).

This build issues with 3.18+ are being tracked in debian
as [debian bug 773713][deb773713], there are proposed patches in the BTS.

### Known workaround:

FIXME apply the patches from BTS

### Work left to do:

Wait for [bug 773713][deb773713].

[broadcom-sta-dkms]: https://packages.debian.org/jessie/broadcom-sta-dkms
[deb773713]: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=773713

---

## Hibernation

Out of the box, the laptop can suspend/resume just fine. However, if you
hibernate it, it will freeze while waking up (screen is blank but the
backlight is on, and the fans start spinning after a while -- I'm
assuming some kind of endless loop resulting in the processor getting hot)

Going through the steps from the kernel doc's [basic-pm-debugging] article,
I found that all `pm_test` steps work just fine, as did the `init=/bin/bash`
minimal environment, so the documentation suggested it must be one of the
loadable modules.

Using a [hibernate-tester] tool I wrote specifically to figure out which one,
I found that having the `i2c-designware-platform` module loaded breaks wakeup
from hibernation.

### Known workaround:

Just `rmmod i2c-designware-platform` before hibernation and
`modprobe i2c-designware-platform` after resume.

If you're using `systemd`, you can drop a simple script ([example script]) into the
`/lib/systemd/systemd-sleep/` directory to automatically un-load the module when
going into hibernation and re-loading it on wakeup. Make sure this script
is owned by `root` and executable
(`chown root:root /path/to/script; chmod +x /path/to/script`)

### Work left to do:

FIXME: report issue to debian bugtracker

[basic-pm-debugging]: https://www.kernel.org/doc/Documentation/power/basic-pm-debugging.txt
[hibernate-tester]: https://github.com/dannyedel/hibernate-tester
[example script]: /assets/downloads/remove-faulty-module

---

## Bluetooth

lsusb:

```
FIXME lsusb
```

The device contains a BCM43142 hybrid WLAN/Bluetooth chipset, and while
there is a debian package that can be installed for WLAN, I did not
find any support for the bluetooth component (which, oddly enough,
connects via USB and is listed as a LiteOn device).

An askubuntu.com [thread about the BCM43142][BCM43142-thread] suggested
this is due to a binary firmware issue. (Note that their usb-id is
`0a5c:21d7`, which is different from the Aspire's)

Further google'ing revealed that on debian jessie, the btusb module
needs to be patched to actually load the modules. Refer to
Dhanar Adi Dewandaru's post about
[getting his BCM43142 to work on jessie][bcm43142-on-jessie]
for the heavy lifting, but note that he also has a different
usb-id (`105b:e065`).

Big thanks to the original posters for figuring this
all out! The following is just an adaptation for this specific laptop.

Reading through the patches linked at the above articles, I learned the
following things.

* Your kernel needs to be patched to send Broadcom firmware to devices.
It will attempt to send firmware to devices marked as `BTUSB_BCM_PATCHRAM`.
You can check if your kernel already contains the relevant sections with
`grep define.*PATCHRAM drivers/bluetooth/btusb.c` from your linux source tree
* Your kernel has to know that the device `04ca:2009` is one of these "Patchram"
devices. Check with
`grep -i 04ca.*2009 drivers/bluetooth/btusb.c`
if there's any entry at all in your kernel.
* You need the actual binary firmware to send to the device.
Check `dmesg | grep -i blue.*firm`
for any bluetooth-firmware-loading messages.
Here's an example:
  `bluetooth hci0: Direct firmware load for brcm/BCM43142A0-04ca-2009.hcd failed with error -2`

### Patching the kernel
There needs to be an entry in the btusb.c source to inform the driver
that `04ca:2009` is one of these patchram devices.
See the [commit 8f0c304][git8f0c304] for the exact format.

After patching, rebuild `btusb.ko` (make modules) and insmod it.
Your syslog should tell you that it tried to load the modules.

### Obtaining the binary firmware from the windows drivers
On my laptop, there was a windows driver DVD included, so I started to check
for files that might be appropriate for this device.

I ran the command
`grep -HinR '04ca.*2009' autorun/drv/hai\ wireless+bt\ 3rd\ wifi\ 1x1bgn+bt4.0\ bcm43142/`
from the DVD's root dir to scan for `inf` files about the driver.

The lines it found pointed me towards the `BlueRAMUSB2009` section
in the file `/bcbtums-win8x64-brcm.inf`.

That section pointed me towards a file named
`BCM43142A0_001.001.011.0197.0211.hex` --
I am assuming this is the correct firmware for the device.

With Jesse Sung's [hex2hcd] utility, I compiled it to the format
and filename that btusb expected:
`./hex2hcd ../bcm43142a0_001.001.011.0197.0211.hex BCM43142A0-04ca-2009.hcd`

Copying that file to `/lib/firmware/brcm/`, followed by a fresh
`rmmod btusb` and `insmod btusb.ko` resulted in the bluetooth
*actually working* - I was able to use my phone as a bluetooth-mouse
for the laptop, while browsing the internet (to verify Wi-Fi working
simultaneously)

### Work left to do

FIXME: Report this to debian bugtracker

FIXME: Figure out if this binary firmware can be downloaded
from the internet

FIXME: Check at which kernel version the PATCHRAM support was mainlined

[git8f0c304]: http://git.kernel.org/cgit/linux/kernel/git/stable/linux-stable.git/commit/?id=8f0c304c693c5a9759ed6ae50d07d4590dad5ae7
[hex2hcd]: https://github.com/jessesung/hex2hcd
[BCM43142-thread]: http://askubuntu.com/questions/533043/bluetooth-not-working-on-ubuntu-14-04-with-dell-inspiron-15-3521
[bcm43142-on-jessie]: http://dhanar10.blogspot.de/2014/05/bcm43142-bluetooth-getting-it-to-work.html
