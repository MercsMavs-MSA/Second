---
title: "Web App Versions"
description: "Select a deployed version of the SECOND web application to launch."
---

Select a deployed version of the SECOND web application below to launch.

## Latest Commit Build

{{< callout type="warning" >}}
This release is experimental, and may not work correctly. Use at your own risk.
{{< /callout >}}

[% if latest_commit %]
{{< cards >}}
  {{< card link="./latest/" title="Commit [[ latest_commit ]]" icon="code" subtitle="Latest build compiled directly from default branch" >}}
{{< /cards >}}
[% else %]
*No commit build available.*
[% endif %]

## Tagged Releases

[% if tags %]
{{< cards >}}
[% for tag in tags %]
  {{< card link="./[[ tag ]]/" title="Release [[ tag ]]" icon="tag" subtitle="Official release [[ tag ]]" >}}
[% endfor %]
{{< /cards >}}
[% else %]
*No tagged release versions available.*
[% endif %]
