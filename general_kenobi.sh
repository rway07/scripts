#!/bin/bash
# Backup directories
BACKUP_DIR_NORMAL="/home/centos/backup/database/normal/"
BACKUP_DIR_FULL="/home/centos/backup/database/full/"
BACKUP_DIR_ROUTINES="/home/centos/backup/database/routines/"

# Mega backup directories
MEGA_BACKUP_DIR_NORMAL="/Root/sparda_database_backup/normal/"
MEGA_BACKUP_DIR_FULL="/Root/sparda_database_backup/full/"
MEGA_BACKUP_DIR_ROUTINES="/Root/sparda_database_backup/routines/"

# Name prefixes
NAME_PREFIX_NORMAL="ldp_backup_"
NAME_PREFIX_FULL="ldp_full_backup_"
NAME_PREFIX_ROUTINES="ldp_routines_"

# File names 
FILENAME_NORMAL=$NAME_PREFIX_NORMAL$(date '+%Y-%m-%d_%H-%M').sql
FILENAME_FULL=$NAME_PREFIX_FULL$(date '+%Y-%m-%d_%H-%M').sql
FILENAME_ROUTINES=$NAME_PREFIX_ROUTINES$(date '+%Y-%m-%d_%H-%M').sql

# Database data
DB_NAME="linea_del_parco"
DB_USER="root"

# Mysqldump configuration file
MYSQLDUMP_CONF_FILE="/etc/mysqldump.cnf"

# Mode arguments
NORMAL_ARGS="--single-transaction "
FULL_ARGS="--single-transaction --routines "
ROUTINES_ARGS="--routines --no-create-info --no-data --no-create-db --skip-opt "

# Display the help message
help()
{
    printf "Usage: kenobi [options] mode\n"
    printf "options:\n"
    printf " --silent      Silent mode for cron use case\n"
    printf " --upload      Upload file to Mega\n"
    printf " --compress    Compress file\n"
    printf " --out FILE    Save the dump on a custom file\n"
    printf "\n"
    printf "Modes:\n"
    printf " normal        Normal backup (only database)\n"
    printf " routines      Routines backup (only routines and stored procedures)\n"
    printf " full          Full backup (database and routines)\n"
}


# Upload file to mega
# Params:
# $1 Mega backup directory
# $2 Local backup directory
# $3 Local backup file name
function mega_upload()
{
    # If all the paramater are present
    if [ $# = 3 ]; then
        printf "Uploading to mega...\n"
        # We have to try deleting the backup archive first because megatools do not provide an overwrite option
        megarm "$1$3"

        # Upload the actual file
        if megaput --reload --path "$1" "$2$3"; then
            printf "Done\n"
        else
            printf "Something went wrong with megaput\n"
        fi
    fi
}

# Remove an unnecessary file
# $1 file to remove
function cleanup()
{
    if [ -e "$1" ]; then
        rm "$1"
    fi
}

# Build the various commands to dump the databse
# Params:
# $1 mode args
# $2 dump file name
# $3 local backup path
# $4 remote backup path
# Exit codes:
# 5 mysqldump failed
# 6 gzip failed
function dump_database()
{
    # Command structure
    # mysqldump (silent / user password prompt) (mode: normal - full - routines) (database name) (compress) > (filename)
    # silent:                           --defaults-extra-file=$MYSQLDUMP_CONF_FILE
    # user password prompt:             -u $DB_USER -p
    # normal mode:                      --single-transaction
    # full mode:                        --single-transaction --routines
    # routines mode:                    --routines --no-create-info --no-data --no-create-db --skip-opt TODO: Consider adding --add-drop-table
    # compress:                         gzip executed after the dump
    # TODO variables hold data, functions hold code
    command="mysqldump "

    # Proceed only if all the arguments are present
    if [ "$#" = 4 ]; then
        # Add user interactions options
        if $silent; then
            command+="--defaults-extra-file=$MYSQLDUMP_CONF_FILE "
        else
            command+="-u $DB_USER -p "
        fi

        # Add mode options
        command+="$1"

        # Add database name
        command+="$DB_NAME "

        # Set the output filename
        # filename without the complete path is required to use megaput
        if [ -n "$file" ]; then
            filename=$file
            complete_file_path=$3$file
            command+="> $complete_file_path"
        else
            filename=$2
            complete_file_path=$3$2
            command+="> $complete_file_path"
        fi

        # Execute mysqldump
        # I have decided to separate mysqldump and gzip execution in order to obtain the return value and better organize the code
        eval "$command"

        # Proceed only if mysqldump execution went fine
        if [ $? = 0 ]; then
            printf "Done\n"

            # Compress the dump
            if $compress; then
                printf "Compressing...\n"
                # The same with gzip
                if gzip -f "$complete_file_path"; then
                    printf "Done\n"
                    # Add .gz at the end of the file
                    if [[ "$complete_file_path" != *.gz ]]; then
                        complete_file_path="$complete_file_path.gz"
                        filename="$filename.gz"
                    fi
                else
                    printf "Something went wrong with gzip\n"
                    # Cleaning up the leftovers
                    cleanup "$complete_file_path"
                    exit 6
                fi
            fi

            # If the upload flag is enabled, we call the power of mega
            if $upload; then
                mega_upload "$4" "$3" "$filename"
            fi
        else
            printf "Something went wrong with mysqldump, ask for guru meditation\n"
            # Cleaning up the leftovers
            cleanup "$complete_file_path"
            exit 5
        fi
    fi
}

# Command parser
function command_chooser()
{
    case "$1" in
        normal)
            printf "Dumping database...\n"
            dump_database "$NORMAL_ARGS" "$FILENAME_NORMAL" "$BACKUP_DIR_NORMAL" "$MEGA_BACKUP_DIR_NORMAL"
            ;;
        full)
            printf "Dumping database and routines...\n"
            dump_database "$FULL_ARGS" "$FILENAME_FULL" "$BACKUP_DIR_FULL" "$MEGA_BACKUP_DIR_FULL"
            ;;
        routines)
            printf "Dumping routines...\n"
            dump_database "$ROUTINES_ARGS" "$FILENAME_ROUTINES" "$BACKUP_DIR_ROUTINES" "$MEGA_BACKUP_DIR_ROUTINES"
            ;;
        *)
            printf 'Invalid mode: %s\n' "$1"
            help
            ;;
    esac
}

# We can say that the script begin here
compress=false
silent=false
upload=false
SHORT_OPTS=c,s,u,o:,h
LONG_OPTS=compress,silent,upload,out:,help
OPTS=$(getopt -a -n kenobi --options $SHORT_OPTS --longoptions $LONG_OPTS -- "$@")

# Exit if getopt does not recognize some options
# exit code 4: trouble with argument parsing
if [ $? -ne 0 ]; then
    help
    exit 4
fi

eval set -- "$OPTS"

# Options parsing logic
while :
do
    case "$1" in
        -c | --compress )
            compress=true
            shift
            ;;
        -s | --silent )
            silent=true
            shift
            ;;
        -u | --upload )
            upload=true
            shift
            ;;
        -o | --out )
            file=$2
            shift 2
            ;;
        -h | --help)
            help
            exit 2
            ;;
        --)
            mode=$2
            # At this point, the arguments left are -- and the actual mode
            # If there are more than two elements, somethins is off, and we exit because we do not like garbage
            if [ $# = 2 ]; then
                command_chooser "$mode"
            elif [ $# = 1 ]; then
                # Mode missing, need any help?
                help
            else
                printf "Mode is only one word, check the arguments\n"
            fi
            shift
            break
            ;;
        *)
            printf "Congratulations, you got here, now try to figure out why"
            break
            ;;
    esac
done 
