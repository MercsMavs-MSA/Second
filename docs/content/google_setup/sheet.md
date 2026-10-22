---
title: "Template Sheet"
weight: 20
---

A template Google Sheet for _Second_ is provided [here](https://docs.google.com/spreadsheets/d/1oSpvY5a2ia-BMnCmbfHnVarhzfLuNhgHjvAtxOJZANI/edit?usp=sharing). Make a copy of it.

**Make the [service account](/google_setup/account/)'s email an editor of your copy.** The app will not work if it doesn't have access to the sheet.

## Getting the Sheet's ID

The sheet ID can be retrieved from the URL of your copy.

For example the ID of `https://docs.google.com/spreadsheets/d/1oSpvY5a2ia-BMnCmbfHnVarhzfLuNhgHjvAtxOJZANI/edit?gid=2019486561#gid=2019486561`

Is: **`1oSpvY5a2ia-BMnCmbfHnVarhzfLuNhgHjvAtxOJZANI`**

## Members Sheet

This sheet contains each member's unique ID, name, role (admin or student), presence, location, and password hash (only used for admins).

The template above includes examples for admin and student accounts

### Adding more members

More members can be added by duplicating existing member rows and changing their attributes.
By default, **it may take up to 90 seconds before new members are populated in the kiosks**.

{{< callout type="info" >}}
Ensure that each member's ID is unique. _Second_ is not able to handle duplicate IDs, and will behave unexpectedly.
{{< /callout >}}

### What is the Password Hash?

The password hash is a SHA256 hash of the admin's password.

### Resetting an Admin's PIN

Simply clear the password hash from the sheet.
The admin will be asked to create a new PIN on the kiosk the next time they sign in.

## Log Sheet

The log sheet contains a list of each member's sign in and out activity.
Kiosks that are authenticated into the sheet will add new lines to this sheet every time someone clocks in or out.
Timestamps and clock in location (if clocking in) will be recorded here.

{{< callout type="warning" >}}
Do not manually modify the sheet's header (row 2). The app may not function correctly if anything is changed.
{{< /callout >}}
