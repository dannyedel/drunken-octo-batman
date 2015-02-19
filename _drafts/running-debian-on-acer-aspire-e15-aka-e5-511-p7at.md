---
title: "Running Debian GNU/Linux on an Acer Aspire E15 (aka E5-511-P7AT)"
---

This page describes the issues I faced while trying to get a debian
installation running on the Acer `Aspire E15`, also known as
`E5-511-P7AT`. After applying some workarounds I was able to run
*everything*.

Note that debian *wheezy* did not work very well, the in-kernel driver
for the integrated graphics card is simply too old.

Known issues and workarounds:

## BUG: X freezes when connecting an external graphics card

This is a bug in the i915 driver -- connecting an external screen
(for example, while on the gdm login manager)
results in a lockup, duplicating the (previously internal) contents.

![screen locking up example](/assets/images/acer-screen-lockup.jpg)

### Known workaround:
Install a linux kernel >= 3.19, for example from
[debian snapshots' kernel images][snapshotlinux].

I have [reported this issue][deb778604] to the debian bugtracker,
hoping to backport the driver to jessie.

### Work left to do:

See if it's possible to backport the i915 driver to jessie's kernel.
Look at [debian bug 778604][deb778604] for status on that.

[snapshotlinux]: http://snapshot.debian.org/package/linux/
[deb778604]: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=778604

## Wireless LAN driver

Install the [broadcom-sta-dkms] package from `non-free` to get the `wl`
kernel module.

### Known issue:
broadcom-sta-dkms (at least version `6.30.223.248-3`) does not build
correctly on 3.18+ kernels (Which I was using because of the `i915`
issue)

This issue is being tracked in debian as [debian bug 773713][deb773713],
there are proposed patches in the BTS.

[broadcom-sta-dkms]: https://packages.debian.org/jessie/broadcom-sta-dkms
[deb773713]: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=773713

## Wakeup from hibernation does not work

Going to hibernation works, also every `pm_test` step from the
kernel documentation's [basic-pm-debugging] worked.
The documentation suggested one of the
loadable kernel modules is likely the problem.

Using a [hibernate-tester] tool I wrote specifically to figure out which one,
I found that having the `i2c-designware-platform` module loaded breaks wakeup
from hibernation.

### Known workaround:

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

## Bluetooth driver

The device contains a BCM43142 hybrid WLAN/Bluetooth chipset, which doesn't work
out-of-the-box.

An askubuntu.com [BCM43142-thread] suggested this is due to a binary firmware
issue.
Further google'ing revealed that on debian jessie, the btusb module
needs to be patched to actually load the modules. Refer to
`dhanar10.blogspot.de`'s post about [bcm43142-on-jessie] for details
and the generic idea (thanks for figuring this all out!).

Since I was already using a custom kernel (see above about the intel
i915 driver) I started to research and experiment...

Here's what I know:

* Your kernel needs to be patched to send Broadcom firmware to devices.
It will do this to devices marked as `BTUSB_BCM_PATCHRAM`.
You can check if your kernel contains the relevant sections with
`grep define.*PATCHRAM drivers/bluetooth/btusb.c` from your linux source tree
* Your kernel has to know that the device `04ca:2009` is one of these "Patchram"
devices. Check with
`grep -i 04ca.*2009 drivers/bluetooth/btusb.c`
* You need the actual binary firmware to send there. Check `dmesg | grep -i blue.*firm`
for any bluetooth-firmware-loading messages.
Mine said:
  `bluetooth hci0: Direct firmware load for brcm/BCM43142A0-04ca-2009.hcd failed with error -2`

### Patching the kernel
I added a line to the btusb.c source to inform the driver
that `04ca:2009` is one of these patchram devices.
See the [btusb-patch] for the exact format.

After that, rebuild `btusb.ko` (make modules) and insmod it.
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

[btusb-patch]: /assets/downloads/bcm43142a0.patch
[hex2hcd]: https://github.com/jessesung/hex2hcd
[BCM34142-thread]: http://askubuntu.com/questions/533043/bluetooth-not-working-on-ubuntu-14-04-with-dell-inspiron-15-3521
[bcm43142-on-jessie]: http://dhanar10.blogspot.de/2014/05/bcm43142-bluetooth-getting-it-to-work.html
