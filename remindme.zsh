#!/usr/bin/env zsh
# TODO colorize unread
# TODO mark read using completion function
# TODO periodic command
# TODO update the prompt with an icon using the periodic command
# TODO make read stable with the previous unread

source color.zsh

DATE_FORMAT="%Y-%m-%dT%H:%M:%S" 
DATE_FORMAT_VIEWED="%Y-%m-%dT%H.%M.%S" # periods are git friendlier than colons
delim=" :: "
# FIXME - make it in the home dir
reminders_file=.reminders
read_reminders_file=.reminders-read

function _in() {
    local date_canonical="$(date --date="now + $date" +$DATE_FORMAT)"
    local record=${date_canonical}${delim}${reminder}
    echo $record >> $reminders_file
    _sort $reminders_file
}

function set-reminder() {
    local relation="$1"
    local date_prepend=""
    [[ relation = "relative" ]] && date_prepend="now + "
    local date_canonical="$(date --date="${date_prepend}${date}" +$DATE_FORMAT)"
    local record=${date_canonical}${delim}${reminder}
    echo $record >> $reminders_file
    _sort $reminders_file
}

#inplace sort
function _sort() {
    local file=$1
    [[ ! -e $file ]] && echo $file not found >&2
    local tmp=$(mktemp)
    sort -i $file > $tmp
    mv $tmp $file
}

function _mark-read-multi() {
    for arg in $@; do
        _mark-read $arg
    done
}

function _mark-read() {
    number=$1
    [[ -z $number ]] && \
        echo "Invalid ref: $number." >&2 && \
        return 1
    local tmp=$(mktemp)
    awk -vnumber=$number \
        'NR!=number{print} NR==number{print >> "'"$read_reminders_file"'"}' $reminders_file > $tmp
    mv $tmp $reminders_file
    _sort $read_reminders_file
}

# TODO: tabularize show-unread with date DIFF after
function _show-unread() {
    local printer="$1"
    local date_canonical="$(date --date="now" +$DATE_FORMAT)"
    local reminder="DUMMY"
    local record=${date_canonical}${delim}${reminder}
    echo $record >> $reminders_file
    _sort $reminders_file
    # FIXME: make stable
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
        #echo "${linenum} - ${reminder}|${datediff} ago"
    done < <( awk -F"$delim" -vrec="$record" -vOFS="$delim" \
        '$0==rec{ exit 0 } {print NR, $1, $2}' \
        $reminders_file )
    local tmp=$(mktemp)
    awk -vrec="$record" '$0!=rec{ print }' $reminders_file > $tmp
    mv $tmp $reminders_file
}

function _show-upcoming() {
    local abs=false
    [[ "$1" = "by" ]] && \
        shift && \
        abs=true

}

function _print-pretty() {
    local line="$1"
    local linenum="$(echo $line | awk -F"$delim" '{print $1}')"
    local date="$(echo $line | awk -F"$delim" '{print $2}')"
    local reminder="$(echo $line | awk -F"$delim" '{print $3}')"
    local datediff="$(_smart-date-diff "now" "$date")"
    echo "$(color -b)${linenum}$(color) $(color black)-$(color) $reminder$(color blue) ... $(color -b)$datediff ago$(color)"
}

function _print-completer() {
    #TODO: disambiguate
    local line="$1"
    local linenum="$(echo $line | awk -F"$delim" '{print $1}')"
    local date="$(echo $line | awk -F"$delim" '{print $2}')"
    local reminder="$(echo $line | awk -F"$delim" '{print $3}')"
    echo "$linenum:$reminder @$(_date-convert "${date}")"
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

function remindme() {

    case "$1" in
        "in")
            relation="in"
            shift
            ;;
        "at")
            relation="at"
            shift
            ;;
        "show-unread")
            _show-unread pretty
            return 0
            ;;
        "show-upcoming")
            shift
            _show-upcoming
            return 0
            ;;
        "read")
            shift
            _mark-read-multi $@
            return 0
            ;;
        *)
            relation="at"
            ;;
    esac

    date=""
    reminder=""
    parsedate=true
    for arg in $@; do
        [[ $arg = "--" ]] && \
            parsedate=false && \
            continue
        if { $parsedate }; then
            date="${date}${arg}"
        else
            reminder="${reminder} ${arg}"
        fi
    done

    # trim that first space
    reminder=$(echo $reminder | sed 's/^\s//')

    [[ -z "$reminder" ]] &&
        echo "Please specify a reminder after \"--\""

    local date_prepend=""
    [[ relation = "relative" ]] && date_prepend="now + "

    { date --date="${date_prepend}${date}" &>/dev/null } || \
        { echo "unix date didn't like your date string: \"now + $date\"."; \
            return 1 }
    
    set-reminder $relation
}
