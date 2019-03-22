#!/bin/bash

kernel="kernel"
###Check if the server is OpenVZ node
yum list installed | grep vzkernel.x86_64
if [ "$?" == "0" ]; then

kernel="vzkernel"
fi


###Install vim and yum-utils if missing ### Revised Feb 27 2017

yum list installed | egrep "vim.common|yum-utils" > /tmp/yum-log-tmp
if [ $(grep -ic "yum-utils" /tmp/yum-log-tmp) -eq 0 ]
	then
	echo -e "\nPrerequisites already present \n" > /dev/null 2>&1
	else
	yum install vim yum-utils -y > /dev/null 2>&1
fi



###Finding hostname [Public IP in case of Amazon EC2 instances] ### Jan 13 2017

hostname1="`grep -i amazon /etc/os-release | head -1`" > /dev/null 2>&1
if [[ -z "${hostname1}" ]]
then
	hostname1=`hostname`
else
	hostname1=`curl -s http://169.254.169.254/2009-04-04/meta-data/public-ipv4` > /dev/null 2>&1
fi


###Alert and stop if Reboot pending after kernel upgarde ### Feb 27 2017

var1=$(rpm -q --last $kernel | perl -pe 's/^kernel-(\S+).*/$1/' | head -1)
yum list installed | grep vzkernel.x86_64
if [ "$?" == "0" ]; then
var1=$(rpm -q --last vzkernel | perl -pe 's/^vzkernel-(\S+).*/$1/' | sed 's/.x86_64//g' |head -1)
fi

openvz_container="package                                       kernel is not installed"

var2=$(uname -r)
if [ "$var1" == "$var2" ]
        then
        echo "No reboot pending" >> /dev/null 2>&1
elif [[ `rpm -q --last kernel | perl -pe 's/^kernel-(\S+).*/$1/' | head -1 | grep "kernel is not installed"` ]]
    then
    yum update -y >> /tmp/yum-log 2>&1
    exit 0

else
        printf "Reboot Pending: Kernel has been already updated and please schedule a reboot at the latest\nCurrent kernel loaded:`echo $var2`\nLatest kernel installed:`echo $var1`" | /usr/bin/tr -cd '\11\12\15\40-\176' | mail -s "Reboot Pending: Kernel already updated in $hostname1"  -r admin@connaxis.hosting admin@connaxis.hosting
exit 0
fi


###Kernel first attempt one
echo -e "\nKernel update attempt: `date`\n===================\n" > /tmp/yum-log
yum update -y >> /tmp/yum-log 2>&1

###Post-upgrade Variable declaration
s1=$(rpm -q --last $kernel | perl -pe 's/^kernel-(\S+).*/$1/' | head -1)
yum list installed | grep vzkernel.x86_64
if [ "$?" == "0" ]; then
s1=$(rpm -q --last vzkernel | perl -pe 's/^vzkernel-(\S+).*/$1/' | sed 's/.x86_64//g' |head -1)
fi

s2=$(uname -r)
boot_size="`df -T | grep "/boot" | awk '{print $3}'`"

###Check for errors in first attempt and retry kernel update
if [ $(egrep -ic "Transaction Check Error|on the /boot filesystem" /tmp/yum-log) -gt 0 ]
	then
	###Remove old kernels considering /boot partition
	echo -e "\n\nOld Kernel removal attempt: `date +%r`\n===================\n" >> /tmp/yum-log
	if [[ -z "${boot_size}" ]]
	then 
		echo "No seperate boot partition"
	elif [[ "$boot_size" -lt "112640" ]]
	then 
		package-cleanup --oldkernels --count=1 -y >> /tmp/yum-log 2>&1
	else 
		package-cleanup --oldkernels --count=4 -y >> /tmp/yum-log 2>&1
	fi
	###Kernel update second attempt
	echo -e "\n\nKernel update second attempt: `date +%r`\n===================\n" >> /tmp/yum-log
	yum update -y >> /tmp/yum-log 2>&1

	###Converting dos characters to unix format ### Jan 13 2017
	vim /tmp/yum-log +"%s/\r/\r/g" +wq
	
	###Checking whether kernel is updated the second time
	s1=$(rpm -q --last $kernel | perl -pe 's/^kernel-(\S+).*/$1/' | head -1)
	yum list installed | grep vzkernel.x86_64
    if [ "$?" == "0" ]; then
        s1=$(rpm -q --last vzkernel | perl -pe 's/^vzkernel-(\S+).*/$1/' | sed 's/.x86_64//g' |head -1)
    fi

	if [ "$s1" == "$s2" ]
		then
		printf "An error has been encountered upon executing the kernel update script and the old kernel removal had been attempted. Please see the log below: \n `cat /tmp/yum-log`"| /usr/bin/tr -cd '\11\12\15\40-\176' | mail -s "Kernel update Error in $hostname1"  -r info@adminbirds.com info@adminbirds.com
	else 
		printf "Kernel updated.\n\n[UPDATE] kernel update has been complete. Please see the log below: \n `cat /tmp/yum-log`" | /usr/bin/tr -cd '\11\12\15\40-\176' | mail -s "Kernel updated in $hostname1"  -r info@adminbirds.com info@adminbirds.com
	fi
elif [ "$s1" == "$s2" ]
	then
	echo "Kernel not updated" >> /tmp/yum-log
else
	printf "Kernel has been updated and please schedule a reboot" | /usr/bin/tr -cd '\11\12\15\40-\176' | mail -s "Kernel updated in $hostname1"  -r info@adminbirds.com info@adminbirds.com
fi

#### Clean up /boot partition if present and almost full.### Feb 27 2016

temp=`df -h |grep '/boot' | head -1 |awk '{print $5}' | sed 's/\%//g'`;
if [ "$temp" != ""  ];then
if (($temp > 90)); then
echo -e "\nCleaning up old kernel\n"
package-cleanup --oldkernels --count=1 -y >> /tmp/yum-log 2>&1
fi
fi

