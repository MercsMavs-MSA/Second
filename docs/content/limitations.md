---
title: "Limitations"
weight: 60
---

## Google Sheet Sizes

### Workbooks

- 10 million cells
- 18,278 columns
- 200 sheets
- Update 40,000 rows at once

## Google Sheet API Limits

### Read

- 300 per minute per project
- 60 per minute per user per project

{{< callout type="info" >}}
This is effectively the limit for the attendance tracker unless each station is configured as a different user
{{< /callout >}}

### Write

- 300 per minute per project
- 60 per minute per user per project

{{< callout type="info" >}}
It is recommended to use a separate Google Service Account for each kiosk.
{{< /callout >}}
