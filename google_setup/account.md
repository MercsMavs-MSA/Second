# Google Service Accounts

_Second_ uses a Google Sheet for member lists, status tracking, and log keeping. _Second_ requires a [Service Account](https://cloud.google.com/iam/docs/service-account-overview) to authenticate with Google. This guide will walk you through the steps for setting up a service account with access to the Google Sheets API.

{{< callout type="warning" >}}
You must have the ability to use the Google Cloud Console within your organization. (Only applicable if you are in an organization account)
{{< /callout >}}

## Creating a Google Cloud Project

For the Attendance Tracker to be able to talk to Google then the Google Sheet needs to be associated with a `Google Project`.

To create a project go to [https://console.cloud.google.com/projectselector2/](https://console.cloud.google.com/projectselector2/).

Click "Create Project"

On the next window, for the Project Name use "Attendance Tracking".

![gcloud_new_project.png](/media/gcloud/gcloud_new_project.png)

Click "Create".

Next you should see a "welcome" screen and indicate "You're working in Attendance Tracking".

![gcloud_project_welcome.png](/media/gcloud/gcloud_project_welcome.png)

## Adding the Google Sheets API

Click "View all APIs"

![gcloud_view_apis.png](/media/gcloud/gcloud_view_apis.png)

Search and Select "Google Sheets API"

![gcloud_search_gsheets.png](/media/gcloud/gcloud_search_gsheets.png)

Click "Enable" under the API

![gcloud_enable_api.png](/media/gcloud/gcloud_enable_api.png)

## Creating the Service Account

Once the API is enabled, you should be redirected to the "APIs & Services" page.
Click "Create Credentials".

![gcloud_api_create_creds.png](/media/gcloud/gcloud_api_create_creds.png)

Select "Application Data" and continue.

![gcloud_cred_type.png](/media/gcloud/gcloud_cred_type.png)

Create your service account.
Add a name, ID, and description.

{{< callout type="tip" >}}
It is **highly recommended** to create separate accounts for each kiosk you may be using. Name them something unique.
{{< /callout >}}

![gcloud_service_account_create.png](/media/gcloud/gcloud_service_account_create.png)

{{< callout type="warning" >}}
Note down this email address, it will be used when we create the [Template Sheet](/google_setup/sheet/)
{{< /callout >}}

On the next screen in the "Select a role" dropdown type "editor" then select the Editor entry from the drop-down list then click "continue", then finally "Done".

![gcloud_service_account_role.png](/media/gcloud/gcloud_service_account_role.png)

Click "Continue".

Skip the "Principals with access" section, and click "Done".

## Creating the JSON Credentials for _Second_

Now we need to download the credentials we just created so click the "Credentials" tab in the middle of the window **(NOT the Create Credentials we clicked earlier)**.

![gcloud_api_creds_tab.png](/media/gcloud/gcloud_api_creds_tab.png)

Select your service account's email.

![gcloud_credentials_select_account.png](/media/gcloud/gcloud_credentials_select_account.png)

Go to the "Keys" tab.

![gcloud_account_keys.png](/media/gcloud/gcloud_account_keys.png)

Select "Create new key" under the "Add key" drop-down.

![gcloud_add_key.png](/media/gcloud/gcloud_add_key.png)

Create a "JSON" private key.

![gcloud_create_private_key.png](/media/gcloud/gcloud_create_private_key.png)

Once you click create, a JSON credential file will be downloaded.
Save this file on to a USB drive that you can plug into your kiosk.

{{< callout type="warning" >}}
This file contains the authentication keys for the service account. Store it securely.
{{< /callout >}}

## Next Steps

Now that you have your credentials file, it can be imported into _Second_.

[Create the sheet](/google_setup/sheet/) that _Second_ will use.

