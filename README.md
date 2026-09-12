# Claude Code Lab environment setup guide

## Docker container setup:

1. Navigate to folder containing docker files
2. Run in terminal to build and deploy containers 
  > docker compose up -d --build
3. Execute to check if containers are deployed and running
  > docker ps to check containers are running

4. go to [http://localhost:8081/guacamole] and login as guacadmin/guacadmin to verify access

5. Execute to create users in the linux server
  > docker exec -it claude_workspace create_ubuntu_users.sh
	  >> enter how many users to create

6. verify new users exist
    > docker exec -it claude_workspace getent passwd

<!--
6. Retrieve IP address of claude_workspace container
  * (linux) docker inspect claude_workspace | grep "IPAddress"
  * (windows) docker inspect claude_workspace | findstr "IPAddress"

7. Copy the IP address
-->

## Apache guacamole setup:

1. cd to the scripts directory

2. Execute in a terminal
  
    > wsl ./new_guacusers.sh
	
    >> enter same number of users as above

3. verify guac users and connections - http://localhost:8081/guacamole, user guacadmin/guacadmin

4. login using browser - [http://localhost:8081/guacamole]  and login as userXX/user123 to verify

5. Once logged in execute "claude"

## Cleanup

1. cd to the docker files directory
2. run to remove all including images

  > docker compose down -v --rmi all --remove-orphans 

OR to remove container and keep images
  
  > docker compose down -v --remove-orphans
<!--
## Windows commands:

### setup:

1. cd scripts
2. edit scripts - 	nano new_guacusers.sh
	* $GuacUrl      = "http://192.168.68.102:8081/guacamole"
	* $ConnHost     = "192.168.68.102"

3. Start-Process PowerShell -ArgumentList '-File "new_guacusers.ps1"' -Verb RunAs
4. verify guac users and connections - http://192.168.68.102:8081/guacamole, user guacadmin/guacadmin


5. install openssh

 	* Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
 	* Set-Service -Name sshd -StartupType 'Automatic'
	* Start-Service sshd
 	* Get-NetFirewallRule -Name *ssh*

6. Start-Process PowerShell -ArgumentList '-File "create_windows_users.ps1"' -Verb RunAs
7. verify new users - Get-LocalUser

8. login using browser - [http://192.168.68.102:8081/guacamole]  and login as userXX/user123 to verify


### cleanup

1. docker compose down --volumes


### alternative method:

1. Import-Module .\GuacamoleAutomation.psm1 -Force
2. New-GuacBulkUsers -GuacUrl "http://192.168.68.98:8080/guacamole" -AdminUser "guacadmin" -AdminPass "guacadmin" -UserCount 5 -ConnName "Labs Machine" -ConnHost "192.168.68.120"
3. Remove-GuacBulkUsers -GuacUrl "http://192.168.68.98:8080/guacamole" -AdminUser "guacadmin" -AdminPass "guacadmin" -UserCount 5 -ConnName "Labs Machine"
-->

