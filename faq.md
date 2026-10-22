# FAQ

## What's the difference between the global admin PIN and an admin member's PIN?

The global admin PIN is used to access the **app's configuration settings and logs**. It is a universal PIN that allows authorized users to manage the app's settings.

An admin member's PIN, on the other hand, is specific to individual admin members stored in the Google Sheet. **This PIN is used for clocking in and out if the admin does not use RFID.**

## What's the difference between an admin member and a regular member?

Admin members are configured by default to require a PIN for manual (non-RFID) clock in/out, while student members do not require a PIN.

## How do I reset the password of an admin member?

Delete the member's "Password Hash" from the Members workbook within the Google Sheet. The member will be prompted to set a new PIN the next time they try to clock in/out.

![reset_admin_pin.png](/media/faq/reset_admin_pin.png)

## What timestamp format is used in the Google Sheets?

Timestamps are recorded in the `<YYYY>-<MM>-<DD>T<HH>:<MM>:<SS>.<microseconds>Z` format. All timestamps are recorded using UTC.

### Example

`2025-09-01T20:23:05.681730Z`

| Component  | Example    | Description                                |
|------------|------------|--------------------------------------------|
| Date       | 2025-09-01 | Date in `YYYY-MM-DD` format                |
| Separator  | T          | Separator between date and time            |
| Time       | 20:23:05   | Time in `HH:MM:SS` format                  |
| Fractional | .681730    | Fractional seconds (microsecond precision) |
| Timezone   | Z          | "Zulu" time indicating UTC (`+00:00`)      |

## Can a physical keyboard be used with the app?

No, a physical keyboard will not work with the app, even if RFID is disabled. The app will only work using the virtual keyboard. This also applies to desktop platforms.

