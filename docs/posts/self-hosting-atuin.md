# Self hosting Atuin Server

Atuin is an awesome....


### Requirements
- You need to be able to run a binary or Docker container on a server.
- You must have either a PostgreSQL, MySQL or SQLite database.

## Setting up what we need in the homelab

For the first requirement we need to be able to run a binary or a Docker container, looks like we're going to need an VM of sorts. Therefore for speed and ease of use we will head over to [Proxmox helper scripts](https://community-scripts.org/) to download a script to spin up a [Ubuntu 22.04](https://community-scripts.org/scripts?type=vm&preview=ubuntu2204-vm) instance.

Once the VM has been generated head to the the Proxmox UI (Cloud-Init). Before starting the VM, go to your Proxmox web UI and click on your newly created Ubuntu VM.Navigate to the Cloud-Init tab. Double-click on User and Password to set the credentials you want to use and your public ssh key. Click Regenerate Image at the top of the menu, and then start the VM.

This now gives us a little VM to run the atuin binary on.
