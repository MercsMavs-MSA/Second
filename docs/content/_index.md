---
title: "SECOND"
cascade:
  type: docs
---

![icon_144.png](/media/logos/icon_144.png)

_SECOND_ is an app to track the attendance of students, mentors, coaches and volunteers to/from events for the purpose of being able to note hours given.

Members and activity logs are stored and managed on a Google Sheet, eliminating the need for complex databases. The app will continue to function locally if the internet connection is lost, and will sync changes when the connection is restored.

{{< cards cols="2" >}}
{{< card link="/Second/google_setup/account/" title="Step 1: Service Account" icon="key" subtitle="Follow the instructions for setting up a Google Service Account and enabling the Google Sheets API." >}}
{{< card link="/Second/google_setup/sheet/" title="Step 2: Template Sheet" icon="table" subtitle="Create a Google Sheet for holding attendance logs, and your member list." >}}
{{< card link="/Second/install/" title="Step 3: Install" icon="download" subtitle="Install _SECOND_ on your desired platform." >}}
{{< card link="/Second/config/" title="Step 4: Configure" icon="cog" subtitle="Configure _SECOND_ with your Google Service Account, Google Sheet information, and team customization." >}}
{{< /cards >}}

## Features

- Supports 300+ members
- Support multiple simultaneous kiosks to allow multiple entry points to the facility.
- Quick and easy to sign in/out
- RFID (HID) support for quick sign in/out (optional)
- Supports team branding with a customizable logo and accent color
- Cross-platform support for Linux (x86 and ARM), macOS (x86 and ARM), Windows (x86 ONLY), Android, iPadOS, and Web
- Open source, expandable and available for anyone to implement
- Support off site events (remote, portable device that can sync in real time with a hotspot or at a later time)
