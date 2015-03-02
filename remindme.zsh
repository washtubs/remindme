#!/usr/bin/env zsh
# TODO establish format for "read" file. include the time the reminder happened and the time it was read

#
# G l o b a l s / i m p o r t s 
# @globals/imports
# {{{

source color.zsh

DATE_FORMAT="%Y-%m-%dT%H:%M:%S" 
DATE_FORMAT_VIEWED="%Y-%m-%dT%H.%M.%S" # periods are git friendlier than colons
# standard string to indicate *unspecified*
na="%%"
delim=" :: "
if (( $+REMINDME_TEST_MODE )); then
    BASE_DIR=$DEV/remindme/remindme-test-data/.remindme
else
    BASE_DIR=$HOME/.remindme
fi
[[ ! -e $BASE_DIR ]] && mkdir -p $BASE_DIR
reminders_file=$BASE_DIR/.reminders
new_reminders_file=$BASE_DIR/.new-reminders
read_reminders_file=$BASE_DIR/.reminders-read
reminder_data_dir=$BASE_DIR/.reminders-data

# }}}

#
# R e m i n d m e   t o p - l e v e l 
# @toplevel
# {{{

function remindme() {
    mkdir "$reminder_data_dir"
    _parse-args $@
}

# }}}

#
# U t i l i t i e s 
# @util
# {{{

#inplace sort
function _sort() {
    local file=$1
    [[ ! -e $file ]] && echo $file not found >&2
    local tmp=$(mktemp)
    sort -i $file > $tmp
    mv $tmp $file
}

function _smart-date-diff() {
    d1=$(date -d "$1" +%s)
    d2=$(date -d "$2" +%s)

    local sorted_ary
    local -A unsorted_map
    sorted_ary=( years months weeks days hours minutes seconds )
    unsorted_map=(
        years $(( 2592000 * 12 ))
        months $(( 86400 * 30 ))
        weeks $(( 86400 * 7 ))
        days $(( 3600 * 24 ))
        hours $(( 60 * 60 ))
        minutes 60
        seconds 1
    )

    local index=1
    local unit
    while true; do
        unit=$sorted_ary[$index]
        local seconds_in_unit=$unsorted_map[$unit]
        local value=$(( (d1 - d2) / $seconds_in_unit ))
        if [ $seconds_in_unit = 1 ]; then
            break
        elif [ $value -gt 0 ]; then
            break
        elif [ $index -gt 7 ]; then
            break
        fi
        (( index++ ))
    done
    echo $value $unit
}

function _date-convert() {
    local date=$1
    echo $(date --date="$date" +"$DATE_FORMAT_VIEWED")
}

function _log() {
    #echo $@ >&2
    echo $@ >/dev/null
}

# }}}

#
# S t a t e   m a n i p u l a t i o n 
# @statemanipulation
# {{{

function _update-reminders() {
    for id in $_ids; do
        _set-reminder $id
    done
}

function _set-reminder() {
    local relation="$_relation"
    local date_prepend=""
    [[ relation = "relative" ]] && date_prepend="now + "
    local date_canonical="$(date --date="${date_prepend}${date}" +$DATE_FORMAT)"
    local id=$1
    if $_edit_mode; then
        if [ -z $id ]; then
            log "edit mode is set. an id was expected."
            return 1
        else
            _update-reminder ${date_canonical} "${reminder}" $id
        fi
    else
        if [ ! -z $id ]; then
            log "edit mode is not set. id unexpected."
            return 1
        else
            _put-record ${date_canonical} "${reminder}"
        fi
    fi
}

function _put-record() {
    local date=$1
    local reminder=$2
    local id
    if [ ! -z $3 ]; then
        id=$3
    else
        if { cd $reminder_data_dir &>/dev/null }; then
            id=$(mktemp XXXXX)
            _log "new record $id"
            echo $reminder > ${id}
            cd - &>/dev/null
        fi
    fi
    local record=${date}${delim}${id}
    echo $record >> $reminders_file
    _sort $reminders_file
    echo $id
}

#updating a date means marking it read
function _update-reminder() {
    local date=$1
    local reminder=$2
    local id=$3
    [[ $# != 3 ]] && echo "invalid usage" && return 1 
    [[ $reminder != "${na}" ]] && \
        echo $reminder > $reminder_data_dir/$id
    if [ $date != "${na}" ]; then
        _mark-read $id
        #re-put the file, the reminder will be ignored
        _put-record $date -- $id
    fi
}

function _mark-read-multi() {
    local id
    for id in $_ids; do
        _mark-read $id
    done
}

function _mark-read() {
    id=$1
    [[ -z $id ]] && \
        echo "No ref given." >&2 && \
        return 1
    local tmp=$(mktemp)
    awk -vid=${id} -F"${delim}"\
        '$2!=id{print} $2==id{print >> "'"$read_reminders_file"'"}' $reminders_file > $tmp
    mv $tmp $reminders_file
    _sort $read_reminders_file
}

# }}}

#
# Q u e r y 
# @query
# {{{

function _get-unread() {
    local date_canonical="$(date --date="now" +$DATE_FORMAT)"
    awk -F"$delim" -vOFS="$delim" -vdate="$date_canonical" \
            'date < $1{ exit 0 } {print $1, $2}' \
            "$reminders_file"
}

# }}}

#
# P r i n t i n g / r e p o r t i n g 
# @printing/reporting
# {{{

# TODO: tabularize show-unread with date DIFF after
function _show-unread() {
    local printer="$1"
    while read line;
    do
        case $printer in
            pretty)
                _print-pretty "$line"
                ;;
            completer)
                _print-completer "$line"
                ;;
        esac
    done < <( _get-unread )
}

function _show-upcoming() {
    local abs=false
    [[ "$1" = "by" ]] && \
        shift && \
        abs=true
}

function _print-pretty() {
    local line="$1"
    local date="$(echo $line | awk -F"$delim" '{print $1}')"
    local id="$(echo $line | awk -F"$delim" '{print $2}')"
    local reminder="$(cat ${reminder_data_dir}/${id})"
    local datediff="$(_smart-date-diff "now" "$date")"
    echo "$(color -b)${id}$(color) $(color black)-$(color) $reminder$(color blue) ... $(color -b)$datediff ago$(color)"
}

function _print-completer() {
    #TODO: disambiguate
    local line="$1"
    local date="$(echo $line | awk -F"$delim" '{print $1}')"
    local id="$(echo $line | awk -F"$delim" '{print $2}')"
    local reminder="$(cat ${reminder_data_dir}/${id})"
    echo "+$id:$reminder ... @$(_date-convert "${date}")"
}

# }}}

#
# C o m m a n d - l i n e   p a r s i n g 
# @commandlineparsing
# functions needed to parse the command-line. They also handle the overall
# program flow
# {{{

# get all ids into global _ids array, and shift as you go
function _parse-ids() {
    _ids=()
    while true; do
        case $1 in
            +*) # identifier
                # parse all identifiers at the beginning
                _ids+=$(echo $1 | sed 's/^+//')
                shift
                continue
                ;;
        esac
        break
    done
    echo $@
}

function _parse-args() {

    _edit_mode=false
    case "$1" in
        "in")
            shift
            _relation="relative"
            _parse-reminder $@
            ;;
        "at")
            shift
            _relation="absolute"
            _parse-reminder $@
            ;;
        "show-unread")
            _show-unread pretty
            return 0
            ;;
        "mark-read")
            shift
            _parse-ids $@ &>/dev/null
            _mark-read-multi
            return 0
            ;;
        "show-upcoming")
            shift
            _show-upcoming
            return 0
            ;;
        "update")
            shift
            _edit_mode=true
            # this is the only argument that requires a second pass
            local t=$(mktemp)
            _parse-ids $@ > $t
            new_args=($(cat $t))
            rm $t
            case $new_args[1] in
                "in")
                    _relation="relative"
                    shift
                    _parse-reminder $new_args[2,-1]
                    ;;
                "at")
                    _relation="absolute"
                    shift
                    _parse-reminder $new_args[2,-1]
                    ;;
                *)
                    _relation="absolute"
                    _parse-reminder $new_args[2,-1]
                    ;;
            esac
            ;;
        *)
            _relation="absolute"
            _parse-reminder $@
            ;;
    esac
}

function _parse-reminder() {
    date=""
    reminder=""
    parsedate=true
    for arg in $@; do
        [[ $arg = "--" ]] && \
            parsedate=false && \
            continue
        if { $parsedate }; then
            date="${date} ${arg}"
        else
            reminder="${reminder} ${arg}"
        fi
    done

    # trim that first space
    reminder=$(echo $reminder | sed 's/^\s//')

    if [ -z "$reminder" ]; then
        if $edit_mode; then
            reminder="${na}"
        else
            echo "Please specify a reminder after \"--\"" >&2
        fi
    fi

    local date_prepend=""
    [[ $_relation = "relative" ]] && date_prepend="now + "

    { date --date="${date_prepend}${date}" &>/dev/null } || \
        { echo "unix date didn't like your date string: \"${date_prepend}$date\"."; \
            return 1 }
    
    if $_edit_mode; then
        _log edit mode enabled
        _update-reminders
    else
        _set-reminder
    fi
}

# }}}

#
# I n t e r a c t i v e   Z s h 
# @interactivezsh
# functions, hooks, and aliases which define the interactive experience
# {{{

function _new-unread() {
    touch $new_reminders_file
    local tmp=$(mktemp)
    comm -23 <( _get-unread ) $new_reminders_file > $tmp
    cat $tmp
    cat $tmp >> $new_reminders_file
}

# periodic function just sets the variable for the shell to handle
function _handle-new-unread() {
    local new_unread
    new_unread=( $(_new-unread) )
    _old_RPROMPT=$RPROMPT
    if [ ! -z "$new_unread" ]; then
        RPROMPT="%{$fg_bold[yellow]%}[[ New reminder! ]]%{$color_reset%}"
    fi
}

function _remove-reminder-flag() {
    if (( $+_old_RPROMPT )); then
        RPROMPT=$_old_RPROMPT
        unset _old_RPROMPT
    fi
}

[[ ! $+PERIOD ]] && PERIOD=10
if ! (( $+_handle_new_unread_set )); then
    periodic_functions+=( _handle-new-unread )
fi
if ! (( $+_remove_reminder_flag_set )); then
    precmd_functions+=( _remove-reminder-flag )
fi
_handle_new_unread_set=true
_remove_reminder_flag_set=true

alias ur="remindme show-unread"
alias mark="remindme mark-read"

# }}}
