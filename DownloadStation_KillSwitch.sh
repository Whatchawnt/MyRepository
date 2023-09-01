#!/bin/bash
#
#
####################################################################################################################################################
####														      How To Use																	####
####################################################################################################################################################
#
# Usage (Recommended):
#             1. Copy the file into a directory (I.E. /volume1/DS920/Synology-SHARE-SHR-Vol1/ )
#			  2. From Synology DSM Open 'Control Panel > Task Scheduler'
#			  3. Select the 'Create' tab and select 'Scheduled Task' from the dropdown menu
#			  4. Select 'User-defined script'
#			  5. Under the 'General' tab enter a task name (i.e. Download Station Kill Switch)
#             6. Select 'root' for the 'User:'
#             7. Select the Schedule tab, select 'Daily' for 'Repeat:' 
#             8. Select '00:00' for start Time.
#             9. Select the checkbox 'Continue running within the same day.'
#             10. Select 'Every minute' for 'Repeat:' and Select '23:59' for 'Last run time:'
#             11. Select the 'Task Settings' tab
#             12. [Optional] Select the checkbox 'Send run details by email' and enter your email
#			  13. Paste the command '/bin/bash <FULL_FILE_PATH>' in the 'User-defined script' text box. 
#				  where <FULL_FILE_PATH> is the path that the script was placed into. May want to place in /usr/local/bin directory
#						o Example: 
#						            /bin/bash /volume1/DS920/Synology-SHARE-SHR-Vol1/DownloadStation_KillSwitch.sh
#						            /bin/bash /volume1/DS920/Synology-SHARE-SHR-Vol1/DownloadStation_KillSwitch.sh -t tun0
#             14. Enter your password
#
#	
# Description:This script checks the messages logs (default: /var/log/messages) to see if a failure occured on the vpn interface (default: tun0).  #
#			  The script grabs the VPN output within the log and if it encounters a recent DOWN state, or the last state it encountered is 
#			  a DOWN state, it stops the (default: Download Station) package.
#
####################################################################################################################################################


####################################################################################################################################################
####                                          Example of how to trigger auto shutdown of Package												####
####################################################################################################################################################
#
# 1. Log into your Synlogy System via SSH.
# 2. Elevate your privileges to root
# 3. Run the below code snippit (assuming default setup) to emulate a shutdown trigger. 
#    Before running this snippit (for test purposes only) make sure to uncomment the variable "messagesLogTest" and comment out the variable "messagesLog" till the end of testing  
#		#curDateTime=$(date '+%Y-%m-%d %H:%M:%S%:z'); echo $curDateTime; curDateTimeSeconds=$(date --date="$curDateTime" '+%s'); echo "curDateTimeSeconds=$curDateTimeSeconds"; issueText="tun0 is down"; echo "$curDateTime $issueText";curDateTime_withT="${curDateTime/ /T}"; outputExample="$curDateTime_withT $issueText"; echo "$outputExample" >> /var/log/messages-test; echo "outputExample=$outputExample"; sleep 1; echo ""; echo "Starting..."; ./DownloadStation_KillSwitch.sh
#
#	*Note: If the name of the interface for your systems VPN is not "tun0" modify this test example as well as the variable 'DOWN_STATE' in the script.
#	       If using the Example above make sure to first set the variable  in this script 	
#
#   Desctiption:
#				- Checks the messages logs to see if a failure occured on the vpn (default: "tun0")
#				- Gets the last couple lines of the VPN output within the /var/log/messages and if its down, runs a stop command to
#                 stop the Download Station package.
################################################################################################################################################


#********************************************************************************************************************************************************
#****************************************************************** [DO NOT EDIT] ***********************************************************************
#********************************************************************************************************************************************************

#Reset Color Back to default
COLOR_RESET=$'\033[0m'
#Used to display Error text in red
RED=$'\033[0;31m'
#Used to display Warning test in Yellow
YELLOW=$'\033[33m'

SCRIPT_NAME=$(basename $0)

helpOption="--help"
tunnelOption="-t"

function print_usage () {
	echo ""
	echo "Usage: ${SCRIPT_NAME} [-t tunnelName]"
	echo ""
	echo "Options:"
	echo ""
	echo "	-t tunnelName			The network Interface for the tunnel"
	echo ""
	echo "	--help				Produces usage text for this script"
	echo ""
	echo "Examples:"
	echo "	${SCRIPT_NAME}"
	echo "	${SCRIPT_NAME} -t tunnelName"
}

OPTS=$(getopt -q -o t: -l help -- "$@")

#the maximum amount of time an instance of the script can take
#This value is chosen due to the fact that this is the minuimum frequency that a Synology task user script can periodically be called
MAXIMUM_ALLOTTED_TIME_SECONDS=60
#********************************************************************************************************************************************************


#check if this was run as root, Else close the program
if [ "$(id -u)" -ne 0 ]
then 
	echo "Please run as root." 
	exit 1
else
	#number of times to run this script per script call before exiting the script
	numberOfScriptRunsPerCall=90
	sleeptimer_Seconds=0.5
	
	#get the current Date-Time the script began and convert it to the format: %Y-%m-%d %H:%M:%S%:z
	scriptStartDateTime=$(date '+%Y-%m-%d %H:%M:%S%:z')
	scriptStartDateTime_Seconds=$(date --date="$scriptStartDateTime" '+%s')
	
	#Used and Assigned later to get the current Date-Time and convert it to the format: %Y-%m-%d %H:%M:%S%:z
	curDateTime=""
	curDateTime_Seconds=""
	

	#If not arguments were passed, set the default tunnel to tun0
	if [ $# -eq 0 ]
	then 
		#Use tun0 as default value (when nothing ius passed in by argument by the user
		tunnelName="tun0"
	else
		#Verify the arguments passed in by the user. If no Argument was passed in default to using the default interface tunnel interface (tunnelName = tun0)
		for OPTION in "$@"
		do
			echo "[~]value of (#): $#"
			if [ $# -eq 2 ]
			then 
				if [ "$OPTION" == "$tunnelOption" ]
					then
						if [[ ! -z "$2" ]]
						then
							#Verify the user did NOT pass in "--help" instead of a value for -t argument.
							if [[ "$2" != "$helpOption" ]]
							then
								tunnelName=$2
								#Shift the entry over by 2
								shift 2
							#If the user passes in "--help" instead of a value for -t argument.
							else
								print_usage
								exit 0
							fi
						else
							echo "${RED}[ERROR] - no parameter privided for '$1'${COLOR_RESET}"
							print_usage
							exit 1
						fi
					else
						echo "${RED}[ERROR] - Unknown option '$1'${COLOR_RESET}"
						print_usage
						exit 1
					fi
			#If 1 or more arguments was passed in
			elif [ $# -ge 1 ]
			#if [ $# -ge 1 ] || [ $# -le 2 ]
			then
				#if the one argument was passed in is the help option, print the help text
				if [[ "$OPTION" == "$helpOption" ]]
				then
					print_usage
					exit 0
				else
					if [ "$OPTION" == "$tunnelOption" ]
					then
						if [[ ! -z "$2" ]]
						then
							#Verify the user did NOT pass in "--help" instead of a value for -t argument.
							if [[ "$2" != "$helpOption" ]]
							then
								tunnelName=$2
								#Shift the entry over by 2
								shift 2
							#If the user passes in "--help" instead of a value for -t argument.
							else
								print_usage
								exit 0
							fi
						else
							echo "${RED}[ERROR] - no parameter privided for '$1'${COLOR_RESET}"
							print_usage
							exit 1
						fi
					else
						echo "${RED}[ERROR] - Unknown option '$1'${COLOR_RESET}"
						print_usage
						exit 1
					fi
				fi
			#Greater than 2 argument or paramaters total
			elif [ $# -gt 2 ]
			then
				print_usage
				exit 1
			#Unknown Error case (this case should not ever occur)
			else
				#echo "${RED}[ERROR] - Unknown Error occurred.${COLOR_RESET}"
				#exit 1
				
				echo "breaking out of for loop..."
				break
			fi
		done
	fi


	#Run the script check for "$numberOfScriptRunsPerCall" number of times
	for (( numTimesRan=0 ; numTimesRan < numberOfScriptRunsPerCall; numTimesRan++))
	do
		#the value of tunnelName variable without the number
		tunnelNameWithoutNumber="${tunnelName//[0-9]/}"

		#get the current Default GateWay if its similar to the base name of $tunnelName without the number. And only match on 1st line (-m)
		defaultGateWay=$(ip route | grep default | grep -oE -m 1 ${tunnelNameWithoutNumber}[0-9]+)
	
		#The Name of the Package
		packageName="DownloadStation"

		#Check to see if the DownloadStattion package is even running
		statusChecker=$(sudo synopkg status "$packageName")

		#Used for comparison later of the 'synopkg status $packageName' command output.
		status_Running='"package":"'$packageName'","status":"running"'
		status_Stopped='"package":"'$packageName'","status":"stop"'

		#get the current Date-Time and convert it to the format: %Y-%m-%d %H:%M:%S%:z
		curDateTime=$(date '+%Y-%m-%d %H:%M:%S%:z')
		curDateTime_Seconds=$(date --date="$curDateTime" '+%s')

		#Function for stopping the Download Station Package
		function stop_download_station () {
			#number representing thhe last attempt to kill a process
			lastTry="2"
			#Only used for comparison in C-type for loop
			lastTryPlusOne=$((lastTry + 1))

			#Run the stop command
			synopkg stop "$packageName" &> /dev/null
			packageRespense=$(sudo synopkg status "$packageName")
			#Check to see if the the package was properly stopped
			if [[ $packageRespense =~ $status_Stopped ]]
			then
				echo "[$curDateTime] Successfully stopped the package: $packageName"
			else
				#Retry A maximum of 3 times before giving up
				for (( count=0 ; count < $lastTryPlusOne; count++))
				do
					#Check to see if the the package was properly stopped
					if [[ $packageRespense =~ $status_Stopped ]]
					then
						echo "[$curDateTime] Successfully stopped the package: $packageName"
						#Successfully stopped the program so break out of the loop
						break
					else
						#Run the stop command again
						synopkg stop "$packageName" &> /dev/null
						packageRespense=$(sudo synopkg status "$packageName")
						
						if [[ ! $packageRespense =~ $status_Stopped ]] && [[ $count -ge $lastTry ]]
						then
							echo "${RED}[$curDateTime] ERROR - Unable to stop the package '${COLOR_RESET}$packageName${RED}'${COLOR_RESET}"
							exit 1
						fi
					fi
				done
			fi
		}

		#if the default Gateway is not the desginated tunnel, then stop the program if it is running
		if [[ "$defaultGateWay" != "$tunnelName" ]] && [[ $statusChecker =~ $status_Running ]]
		then
			echo "${RED}The default gateway is NOT the VPN!!!${COLOR_RESET}"
			echo "[$curDateTime] Stopping $packageName..."
			#Running stop package command code.
			stop_download_station
		fi

		#if the package is running, then run the below code
		if [[ $statusChecker =~ $status_Running ]]
		then
			#DOWN_STATE vpn text
			#The error string that is displayed when the vpn stops working
			DOWN_STATE="$tunnelName is down"

			#If the VPN status is up
			UP_STATE="$tunnelName is up"

			#If the $DOWN_STATE "tun0 is down" and Time difference was in the last 30 seconds.
			recentFailureTime_Seconds="30"

			#Location of the log file that we are searching on (default: '/var/log/messages')
			messagesLog='/var/log/messages'
			#messagesLogTest variable is Used for Test Purposes only
			#####messagesLogTest='/var/log/messages-test'
			
			#if messagesLog varaible is assigned
			if [[ ! -z $messagesLog ]]
			then 
				messagesLog='/var/log/messages'
			#If $messagesLog is unassigned but $messagesLogTest is assigned, run using test file
			elif [[ -z $messagesLog ]] && [[ ! -z $messagesLogTest ]]
			then
				echo "${YELLOW}WARNING: Running script with test Data...${COLOR_RESET}"
				messagesLog="$messagesLogTest"
			#Else - None of the variables are set.
			else
				echo "${RED}ERROR - Unable to run script, variable 'messageLog' is unassigned.${COLOR_RESET}"
				exit 1
			fi
			
			#The Name of the package that this script will shutdown
			packageName="DownloadStation"

			#get the old value of IFS
			OLD_IFS=$IFS
			IFS=$'\n'
			#Input the response of the command to an array in case there are multiple DOWN_STATE messages
			tunnelResponse_Array=($(grep -i "$DOWN_STATE\|$UP_STATE" "$messagesLog"))
			
			#Build seperate Down and Up State arrays from the tunnelResponse_Array data
			for tunnelInfo in ${tunnelResponse_Array[@]}
			do 
				if [[ "$tunnelInfo" =~ $DOWN_STATE ]]
				then
					#IF the tunnelInfo matches the $DOWN_STATE then add it to the variable tunnelResponseDown_Array
					tunnelResponseDown_Array+=("$tunnelInfo")
				elif [[ "$tunnelInfo" =~ $UP_STATE ]]
				then
					#If the tunnelInfo matches the $UP_STATE then add it to the variable tunnelResponseUp_Array
					tunnelResponseUp_Array+=("$tunnelInfo")
				else
					echo "${RED}ERROR - Unknown state in Tunnel Response. A VPN might never have been set up.${RESET_COLOR}"
					#Set IFS back to the original value
					IFS=$OLD_IFS
					exit 1
				fi
			done

			#Set IFS back to the original value
			IFS=$OLD_IFS

			#Used to obtain the last Entry in the Array
			getLastEntry="-1"

			#If there is atleast 1 entry of DOWN state
			if [[ ! -z "${tunnelResponseDown_Array[@]}" ]]
			then
				#Get the last entry within the tunnelResponseDown_Array array
				lastDownStateInArray="${tunnelResponseDown_Array["$getLastEntry"]}"
			fi

			#If there is atleast 1 entry of UP state
			if [[ ! -z "${tunnelResponseUp_Array[@]}" ]]
			then
				#Get the last entry within the tunnelResponseUp_Array array
				lastUpStateInArray=${tunnelResponseUp_Array["$getLastEntry"]}
			fi
			
			#If tunnel Response is Empty, increase the file search to the whole log file.
			if [[ ! -z "${tunnelResponse_Array[@]}" ]]
			then
				#Grab the last entry in the Array
				lastEntryInArray="${tunnelResponse_Array[$getLastEntry]}"
			else
				echo "${RED}ERROR - No VPN information was found in '$messagesLog'${COLOR_RESET}"
				exit 1
			fi	

			#If the tunnelResponseDown_Array is not empty
			if [[ ! -z "${tunnelResponseDown_Array[@]}" ]]
			then
				#Get the last entry within the tunnelResponseDown_Array array
				if [[ ! -z "$lastDownStateInArray" ]]
				then
					fileTimePattern='^[0-9][0-9][0-9][0-9]\-[0-9][0-9]\-[0-9][0-9](T| )[0-9][0-9]\:[0-9][0-9]\:[0-9][0-9]\-[0-9][0-9]\:[0-9][0-9]'

					if [[ "${lastDownStateInArray}" =~ $fileTimePattern ]]
					then
						#copy the contents of the match into a variable that persist, but first replace the 'T' with a single white space
						timeFromCommand="${BASH_REMATCH[0]//T/ }"
						#remove the hyphen to format the time to match the formatting of the current date time used earlier. 
						#And yes, The duplicate command is necessary.
						timeFromCommand="${timeFromCommand/-/}"
						timeFromCommand="${timeFromCommand/-/}"
						#Change the format to just be in seconds
						timeFromCommand_Seconds=$(date --date="$timeFromCommand" '+%s')
			
						#Calculate the time difference between when the tail command was run and when the. Subtract the Time the command was run from the time this script was run.
						timeDiff_Seconds=$(($curDateTime_Seconds - $timeFromCommand_Seconds))
						#if the value is negative for some reason remove the negative symbol to get the absolute value of time difference
						timeDiff_Seconds=${timeDiff_Seconds/-/}

						singleElementArraySize="1"

						#if the time difference was in the last 180 seconds (default value DOWN_STATE in the script run). Or if the lastEntryInArray is the DOWN State.
						if [ $timeDiff_Seconds -ge 0 ] && [ $timeDiff_Seconds -le $recentFailureTime_Seconds ] || [[ "$lastEntryInArray" == "$lastDownStateInArray" ]]
						then
							#if The Last Entry in Array is the UP State then print a warning to the user
							if [[ "$lastEntryInArray" == "$lastUpStateInArray" ]]
							then
								#If the last entry in the tunnelResponseDown_Array (last DOWN/UP state entry in log file) is the UP state but there is a DOWN state entry within the timeframe of $recentFailureTime_Seconds (default 180 seconds)
								echo "${YELLOW}[$curDateTime] WARNING - Your VPN connection is inconsistant, please remedy this before attempting to restart the package '${COLOR_RESET}$packageName${YELLOW}'${COLOR_RESET}"
							fi
							echo "[$curDateTime] The VPN tunnel: ${DOWN_STATE:0:4} has DOWN state"
							echo "[$curDateTime] Stopping $packageName..."
						
							#Stop download Station Package
							stop_download_station
							
						fi
					elif [[ "${lastUpStateInArray}" =~ $fileTimePattern ]]
					then
						#Last entry is the Up case and it has the correct timestamp format
						echo "The last STATE in the List is the UP STATE"
						exit 0
					else
						echo "${RED}[$curDateTime] ERROR - The Timestamp entries in '${COLOR_RESET}$messagesLog${RED}' are formatted incorectly.${COLOR_RESET}"
						exit 1
					fi
				#If there is no DOWN state outocomes at all (lastDownStateInArray is empty)
				elif [[ -z "$lastDownStateInArray" ]]
				then
					#Check to see if there is any UP state outcomes at all
					if [[ -z "$lastUpStateInArray" ]]
					then
						#This case should never occur since there is already a check in the beginning to verify that there is a UP or DOWN state
						echo "${RED}[$curDateTime] ERROR - Variable 'lastDownStateInArray' and variable 'lastUpStateInArray' are empty${COLOR_RESET}"
						exit 1
					fi
				fi #If the last Entry is $lastUpStateInArray then the VPN is still running properly. 
			fi
		else
			#This script does NOT exit with a value of 1 when the package is not currently running, because this script is meant to be run using Synologies 'Task Scheduler'
			echo "${RED}[$curDateTime] Package '${COLOR_RESET}$packageName${RED}' is not currently running.${COLOR_RESET}"
		fi

		#Run Number: $numTimesRan"
		
		
		#Calculate the time difference between when the tail command was run and when the. Subtract the Time the command was run from the time this script was run.
		elapsedTime_Seconds=$(($curDateTime_Seconds - $scriptStartDateTime_Seconds))
		#if the value is negative for some reason remove the negative symbol to get the absolute value of time difference
		elapsedTime_Seconds=${elapsedTime_Seconds/-/}
		# Used to add time to elapsed time to check if the time will go over 'MAXIMUM_ALLOTTED_TIME_SECONDS'
		adjustTime_Seconds=5
		
		#If the sleep timer is not an integer round the value (since bash cannot handle floatin point values, convert it to an integer)
		sleeptimerRounded_Seconds=$(echo $sleeptimer_Seconds | awk '{print int($1+0.5)}')		
		
		#used as the number to compare if the run time of the script will exceed '$MAXIMUM_ALLOTTED_TIME_SECONDS'
		timeChecker=$(( $elapsedTime_Seconds + $adjustTime_Seconds + $sleeptimerRounded_Seconds ))
		
		#The total time the script should run should not exceed 59 seconds since it is meant to be called by the synology task scheduler. 
		#And the minuimum frequency it can run a script is 60 seconds, before running the script again. So for preperation check the time difference and break out early if it will go over the time limit.
		#elapsed Time since script began: $elapsedTime_Seconds
		
		if [ $timeChecker -ge $MAXIMUM_ALLOTTED_TIME_SECONDS ]
		then 
			#breaking out early. In preperation for next script call from synology task scheduler"
			break
		fi
		
		#Sleep for sleeptimer_Seconds length of time (in seconds)
		sleep $sleeptimer_Seconds
	done
fi

