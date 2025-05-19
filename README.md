# Fail2Ban with Cloudflare Integration (Free Tier)

![Language: Bash](https://img.shields.io/badge/Language-Bash-blue)
![Dependencies: curl, js](https://img.shields.io/badge/Dependencies-curl%2C%20jq-orange)
![License: GPL-3.0](https://img.shields.io/badge/License-GPL%203-green)

This project integrates [Fail2Ban](https://www.fail2ban.org/) with [Cloudflare Security Rules](https://developers.cloudflare.com/security/rules/) to block malicious IP addresses by managing the [Cloudflare custom IP list](https://developers.cloudflare.com/waf/tools/lists/custom-lists/#ip-lists). 
It uses a Bash script to add or remove IPs from a Cloudflare blocklist, triggered by Fail2Ban to detect and ban IPs after failed login attempts (e.g., SSH, FTP, WordPress or Home Assistant, etc.).
The project is designed for Cloudflare's free tier, which allows **1 custom IP list with a maximum of 10,000 IP addresses**, and is inspired by the Python-based approach in [Using Fail2Ban with Cloudflare on a free account](https://kovasky.me/blogs/cloudflare_fail2ban/) by Kovasky Buezo.

## Features
- Automatically bans IPs after exceeding failed login attempts (configurable via Fail2Ban jails).
- Manages a Cloudflare custom IP list (up to 10,000 IPs) using the Lists API, compatible with free-tier accounts.
- Supports IPv4 and IPv6 (with optional `/64` subnet blocking for IPv6).
- Lightweight Bash implementation with minimal dependencies: using `curl` and `jq` for API interactions.
- Integrates with Fail2Ban actions for seamless automation.

## Installation
1. **Set Up Cloudflare**:
   - Log in to your Cloudflare dashboard.
   - Navigate to **My Profile > API Tokens > Create a Token > Create a Custom Token**.
   - Name the token (e.g., `fail2ban`) and grant permissions:
     - **Account > Account Filter List > Edit**
   ![image](https://github.com/user-attachments/assets/8545bf46-6ce9-4a60-8566-bbeec90fe346)

   - Save the token securely.
   - Go to **Manage Account > Configurations > Lists**.
   - Create a new list with:
     - **Type**: IP
     - **Name**: `block_list`
       ![image](https://github.com/user-attachments/assets/b47d9ec1-8d66-437d-82ee-eaf29d955604)

   - Save the **List ID** and your **Account ID** from the dashboard or API. You can obtain this data from the URL when editing the list. The URL looks like: `https://dash.cloudflare.com/<user id>/configurations/lists/<list id>`

2. **Install Fail2Ban** (if not installed):
    ```bash
     sudo apt update && sudo apt install fail2ban
     ```

3. **Install Dependencies**:
   Install `curl` and `jq`:
     ```bash
     sudo apt update && sudo apt install curl jq
     ```
     
4. **Set Up Scripts**:
   
   Place `cloudflare-list.sh` and `cloudflare-list.conf` in `/etc/fail2ban/action.d/`.
   For Docker-based Fail2Ban installation put them in `/data/action.d/` and adjust the paths in `cloudflare-list.conf`.

## Configuration
1. **Cloudflare Security Rule**:
   - Link the `block_list` to a Security Rule for your desired domain (zone):
     - Select your domain, go to **Security > Security Rules > Create Rule**.
     - Set:
       - **Field**: IP Source Address
       - **Operator**: Is in list
       - **Value**: `block_list`
       - **Action**: Block
         ![image](https://github.com/user-attachments/assets/d6fbd69e-4896-4db8-8c1f-a96f9829f382)

     - Save and deploy.

2. **Fail2Ban Jail**:
   - Add the `cloudflare-list` action to your jail, for example, for SSH jail add it to the `action` line (edit `/etc/fail2ban/jail.local` or `/etc/fail2ban/jail.d/sshd.conf`):
     ```ini
     [sshd]
     enabled = true
     maxretry = 3
     bantime = 2h
     findtime = 10m
     # NEW LINE GOES HERE:
     # First line is the default ban action, the second line is this Cloudflare list action
     action = %(banaction)s[port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
              cloudflare-list
     ```
   - Adjust `maxretry`, `bantime`, and `findtime` as needed. Add other jails (e.g., for Nginx) if required.

4. **Configure `cloudflare-list.sh`**:
   - Edit `/etc/fail2ban/action.d/cloudflare-list.sh` to include your Cloudflare credentials:
     - **Account ID**: Your Cloudflare account ID.
     - **List ID**: The ID of the `block_list`.
     - **API Token**: The token created earlier.

### **Setup Verification**
1. Follow the **Installation** and **Configuration** steps.
2. Test the script:
   ```bash
   sudo /etc/fail2ban/action.d/cloudflare-list.sh 192.168.100.100 add
   ```
3. Verify the Cloudflare list in the dashboard should now contain the specified IP.
5. Remove the IP from Cloudflare list:
   ```bash
   sudo /etc/fail2ban/action.d/cloudflare-list.sh 192.168.100.100 del
   ```
