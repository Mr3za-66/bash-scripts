#!/usr/bin/env bash
os_dist=`hostnamectl | grep Operating | awk '{print $3}'`
# This script for automated installation an configuration 2FA for ssh login user

### Check root user run this script

if [  `whoami` != "root" ]
then 
	echo "Error: You must run this scripts whit ROOT privilege"
	exit 1
fi

echo "
 #####  #######    #        #####     #    #     # ####### #     #  
 #     # #         # #      #     #   # #   #     #    #    #     #  
       # #        #   #     #        #   #  #     #    #    #     #  
  #####  #####   #     #    #  #### #     # #     #    #    #######  
 #       #       #######    #     # ####### #     #    #    #     #  
 #       #       #     #    #     # #     # #     #    #    #     #  
 ####### #       #     #     #####  #     #  #####     #    #     #  
 ### #     #  #####  #######    #    #       #       ####### ######  
  #  ##    # #     #    #      # #   #       #       #       #     # 
  #  # #   # #          #     #   #  #       #       #       #     # 
  #  #  #  #  #####     #    #     # #       #       #####   ######  
  #  #   # #       #    #    ####### #       #       #       #   #   
  #  #    ## #     #    #    #     # #       #       #       #    #  
 ### #     #  #####     #    #     # ####### ####### ####### #     # 
                                                                     
"

# Backup from all config files
echo "Create a backup from files to ~/.backup/"
mkdir -p ~/.backup/`date +%Y-%m-%d-%H:%M`
FILES="/etc/pam.d/sshd
/etc/ssh/sshd_config"
for file in $FILES
do
        filename=`echo $file | sed "s|/|-|g"`
        cp $file ~/.backup/`date +%Y-%m-%d-%H:%M`/$filename.backup
done

### install google-pam-authenticator function

installer_2fa(){
case $os_dist in
   Ubuntu|Debian)
	   apt-get update -y
          apt-get install libpam-google-authenticator -y > /dev/null
          ;;
   CentOS)
	   yum update -y
          yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm > /dev/null
          yum install google-authenticator -y > /dev/null
          ;;
   *)
          echo "This script isn't compatible with "$os_dist""
          ;;
esac
}
## run and configuration google-authenticator tools function
2FA_conf(){
read -p "Please enter specific user for set 2FA:: " user
sudo su "$user" -c "google-authenticator -t -d -f -r 3 -R 30 -W"

if [ -f "/etc/pam.d/sshd" ]
then
	gauthInPAM=`grep "pam_google_authenticator" /etc/pam.d/sshd | head -c 4`
	if [ "$gauthInPAM" == "auth" ]
	then
			echo "file configuration dided before"
		else
			echo "Modyfy ssh config file"
			sudo tee -a /etc/pam.d/sshd << END
auth    required      pam_unix.so     no_warn try_first_pass
auth    required      pam_google_authenticator.so
END
			echo "Configuration Successfully done!!"
		fi
	else
		echo "The configuration file isn't exist on server."
	fi
	sudo sed -i 's|#ChallengeResponseAuthentication|ChallengeResponseAuthentication|g' /etc/ssh/sshd_config
        sudo sed -i 's|ChallengeResponseAuthentication no|ChallengeResponseAuthentication yes|g' /etc/ssh/sshd_config

	if [[ -f "/home/$user/.googleauthenticator" ]]
	then
		sudo tee -a /etc/ssh/sshd_config << END
Match User $user
    AuthenticationMethods keyboard-interactive
END
	fi
sudo systemctl restart sshd
sudo systemctl restart ssh
echo "Restart SSH Service"

}
if [ -f "/usr/bin/google-authenticator" ]
then
	echo "google-authenticator package installed befor"
	2FA_conf
else
	installer_2fa
	2FA_conf
fi

