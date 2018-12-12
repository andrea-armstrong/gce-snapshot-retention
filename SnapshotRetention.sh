#!/usr/bin/env bash
# Snapshot retention of GCE disks

export PATH=$PATH:/snap/google-cloud-sdk/current/usr/bin/:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin

usage() {
    echo -e "\nUsage: $0 [-p <project>] [-d <days>] [-w <weeks>] [-m <months>] [-y <years>] [-n <dry_run>]" 1>&2
    echo -e "\nOptions:\n"
    echo -e "    -p    Google project name. [REQUIRED]"
    echo -e "    -d    Number of days to keep daily snapshots.  Snapshots older than this number deleted."
    echo -e "          Default if not set: 7 [OPTIONAL]"
    echo -e "    -w    Number of weeks to keep weekly snapshots. Snapshots older than this number are deleted."
    echo -e "          Default if not set: 4 [OPTIONAL]"
    echo -e "	 -m    Number of months to keep a monthly snapshot. Snapshots that fall on the 1st of the month"
    echo -e "	       that are older than this retention are deleted. Default if not set: 12 [OPTIONAL]"		       
    echo -e "    -y    Number of years to keep annual snapshots. Snapshots older than this number are deleted."
    echo -e "          Default if not set: 5 [OPTIONAL]"
    echo -e "    -n    Dry run: causes script to print debug variables and doesn't execute any"
    echo -e "          create / delete commands [OPTIONAL]"
    echo -e "\n"
    exit 1
}

#
# GET SCRIPT OPTIONS AND SETS GLOBAL VAR
#
setScriptOptions()
{
    while getopts ":p:d:w:m:y:n" opt; do
        case $opt in
            p)
                opt_p=${OPTARG}
                ;;
            d)
                opt_d=${OPTARG}
                ;;
            w)
                opt_w=${OPTARG}
                ;;
	    m)	
	    	opt_m=${OPTARG}
	    	;;
            y)
                opt_y=${OPTARG}
                ;;
            n)
                opt_n=true
                ;;
            *)
                usage
                ;;
        esac
    done
    shift $((OPTIND-1))

    # Project - required
    PROJECT=$opt_p

    # Number of days to keep snapshots
    if [[ -n $opt_d ]]; then
        DAILY_RETENTION=$opt_d
    else
        DAILY_RETENTION=7
    fi

    # Number of weekly snapshots to keep
    if [[ -n $opt_w ]]; then
        WEEKLY_RETENTION=$opt_w
    else
    	WEEKLY_RETENTION=4
    fi

    # Number of monthly snapshots to keep
    if [[ -n $opt_m ]]; then
        MONTHLY_RETENTION=$opt_m
    else
    	MONTHLY_RETENTION=12
    fi

    # Number of annual snapshots to keep
    if [[ -n $opt_y ]]; then
        YEARLY_RETENTION=$opt_y
    else
        YEARLY_RETENTION=5
    fi

    # Dry run
    if [[ -n $opt_n ]]; then
        DRY_RUN=$opt_n
    fi

    # Debug - print variables
    if [ "$DRY_RUN" = true ]; then
        echo "DAILY_RETENTION=${DAILY_RETENTION}"
        echo "WEEKLY_RETENTION=${WEEKLY_RETENTION}"
	echo "MONTHLY_RETENTION=${MONTHLY_RETENTION}"
        echo "YEARLY_RETENTION=${YEARLY_RETENTION}"
        echo "PROJECT=${PROJECT}"
        echo "DRY_RUN=${DRY_RUN}"
    fi
}

# Check if snapshot is a valid weekly snapshot (falls on Sunday) and
# if it's older than weekly retention
ifWeekly()
{
	local snapshotDate=$(date -d "$1" +"%Y%m%d")
	local weeklyRetention=$(date -d "$1-${WEEKLY_RETENTION} weeks" +"%Y%m%d")
	if [[ $(date -d "$1" +"%u") == 7 ]] ; then
		if [[ $snapshotDate -ge $weeklyRetention ]] ; then
			echo "0"
		fi
	else
		echo "1"
	fi
}

# Check if snapshot is a valid monthly snapshot (falls on 1st of month) and 
# if it's older than monthly retention
ifMonthly()
{
	local snapshotDate=$(date -d "$1" +"%Y%m%d")
	local monthlyRetention=$(date -d "$1-${MONTHLY_RETENTION} months" +"%Y%m%d")
	if [ $(date -d "$1" +"%d") == 01 ] ; then
		if [[ $snapshotDate -ge $monthlyRetention ]] ; then
			echo "0"
		fi
	else
		echo "1"
	fi
}

# Check if snapshot is a valid annual snapshot (falls on 1st of year) and 
# if it's older than yearly retention
ifYearly()
{
	local snapshotDate=$(date -d "$1" +"%Y%m%d")
	local yearlyRetention=$(date -d "$1-${YEARLY_RETENTION} years" +"%Y%m%d")
	if [[ ($(date -d "$1" +"%d") == 01) && ($(date -d "$1" +"%b") == "Jan") ]] ; then
		if [[ $snapshotDate -ge $yearlyRetention ]] ; then
			echo "0"
		fi
	else
		echo "1"
	fi
}

deleteSnapshot()
{
	local snapshot=$1
	local gcloud_timestamp="$(gcloud compute snapshots --project $PROJECT describe $snapshot --format="value(creationTimestamp)")"

	# echo "${gcloud_timestamp}"
	if [[ $(ifWeekly "${gcloud_timestamp}") == "0" ]] ; then
		echo "Valid weekly - keeping $snapshot"
	elif [[ $(ifMonthly "${gcloud_timestamp}") == "0" ]] ; then
		echo "Valid monthly - keeping $snapshot"
	elif [[ $(ifYearly "${gcloud_timestamp}") == "0" ]] ; then
		echo "Valid yearly - keeping $snapshot"
	else
		echo "Deleting $snapshot"
		$(gcloud compute snapshots delete --project $PROJECT $snapshot --quiet)
	fi
}

main()
{
	setScriptOptions "$@"

	if [ "$DRY_RUN" = true ] ; then
		exit 1
	fi

	# Start looking at snapshots older than the daily_retention
	from_daily_date=$(date -d "-${DAILY_RETENTION} days" "+%Y-%m-%d")
	echo "Reviewing all snapshots older than $from_daily_date in $PROJECT"

	# create empty array
	local snapshots=()

	# Automatically apply filter to only pull snapshots older than the DAILY retention setting
	local gcloud_response="$(gcloud compute snapshots --project $PROJECT list --filter="creationTimestamp<'${from_daily_date}' AND labels.delete!=never" --uri)"

	# read the gcloud_response and add snapshots to the snapshots array
	while read line
	do
        # grab snapshot name from full URI
        snapshot="${line##*/}"

        # add snapshot to global array
        snapshots+=(${snapshot})
    done <<< "$(echo -e "$gcloud_response")"

    for snapshot in "${snapshots[@]}"; do
    	# delete snapshot
    	deleteSnapshot ${snapshot}
    done
}

####################
##                ##
## EXECUTE SCRIPT ##
##                ##
####################

main "$@"
