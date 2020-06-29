#!/usr/bin/env bash

usage() {
	local old_xtrace
	old_xtrace="$(shopt -po xtrace || :)"
	set +o xtrace
	echo "${script_name} - vCard cleanup utility." >&2
	echo "Usage: ${script_name} [flags] [in-file|-]" >&2
	echo "Option flags:" >&2
	echo "  -h --help          - Show this help and exit." >&2
	echo "  -v --verbose       - Verbose execution." >&2
	echo "  -i --in-file       - Input file. Default: '${in_file}'." >&2
	echo "  -o --out-file      - Output file. Default: '${out_file}'." >&2
	echo "Option steps:" >&2
	echo "  -1 --sort          - Sort cards by FN field. Default: '${step_sort}'." >&2
	echo "  -2 --clean-numbers - Convert phone numbers to xxx-xxx-xxxx format. Default: '${step_clean_numbers}'." >&2
	echo "  -3 --remove-dupes  - Remove duplicate cards. Default: '${step_remove_dupes}'." >&2
	echo "  -4 --combine-cards - Combine data from cards with same FN field. Default: '${step_combine_cards}'." >&2
	echo "Send bug reports to Geoff Levand <geoff@infradead.org>." >&2
	eval "${old_xtrace}"
}

process_opts() {
	local short_opts="hvi:o:1234"
	local long_opts="help,verbose,in-file:,out-file:,\
sort,clean-numbers,remove-dupes,combine-cards"

	local opts
	opts=$(getopt --options ${short_opts} --long ${long_opts} -n "${script_name}" -- "$@")

	eval set -- "${opts}"

	while true ; do
		#echo "${FUNCNAME[0]}: @${1}@ @${2}@" >&2
		case "${1}" in
		-h | --help)
			usage=1
			shift
			;;
		-v | --verbose)
			#set -x
			verbose=1
			shift
			;;
		-i | --in-file)
			in_file="${2}"
			shift 2
			;;
		-o | --out-file)
			out_file="${2}"
			shift 2
			;;
		-1 | --sort)
			step_sort=1
			shift
			;;
		-2 | --clean-numbers)
			step_clean_numbers=1
			shift
			;;
		-3 | --remove-dupes)
			step_remove_dupes=1
			shift
			;;
		-4 | --combine_cards)
			step_combine_cards=1
			shift
			;;
		--)
			shift
			if [[ ${1} ]]; then
				in_file="${1}"
				shift
			fi
			if [[ ${1} ]]; then
				echo "${script_name}: ERROR: Got extra opts: '${*}'" >&2
				usage
				exit 1
			fi
			break
			;;
		*)
			echo "${script_name}: ERROR: Internal opts: '${*}'" >&2
			exit 1
			;;
		esac
	done
}

on_exit() {
	local result=${1}

	echo "${script_name}: Done: ${result}" >&2
}

remove_dos_eol() {
	local line="${1}"

	if [[ "${line: -1}" == $'\r' ]]; then
		line="${line:: -1}"
	fi

	echo "${line}"
}

split_kv() {
	local delimiter=${1}
	local str=${2}
	local -n _split_kv__key=${3}
	local -n _split_kv__value=${4}

	_split_kv__key="${str%%${delimiter}*}"
	_split_kv__value="${str#*${delimiter}}"

	if [[ "${_split_kv__value}" == *${delimiter}* ]]; then
		echo "${FUNCNAME[0]}:${LINENO}: ERROR: Bad str: '${str}'" >&2
		exit 4
	fi
}

split_kv_test() {
	local str
	local k
	local v
	local kd='>'

	str="aaa${kd}bbb"
	split_kv "${kd}" "${str}" k v
	echo "${FUNCNAME[0]}:${LINENO}: '${str}' = '${k}' + '${v}'" >&2

	str="this${kd}should${kd}fail"
	split_kv "${kd}" "${str}" k v
	echo "${FUNCNAME[0]}:${LINENO}: '${str}' = '${k}' + '${v}'" >&2
}

split_field() {
	local delimiter=${1}
	local str="${2}"
	local -n _split_field__fields=${3}

	IFS="${delimiter}" read -ra _split_field__fields <<< "${str}"

	if [[ ! ${_split_field__fields[0]} ]]; then
		unset _split_field__fields[0]
	fi

	local field
	for field in "${fields[@]}"; do
		if [[ ! ${field} ]]; then
			echo "${FUNCNAME[0]}:${LINENO}: ERROR: Empty field: '${str}' => '${field}'" >&2
			exit 4
		fi
	done
}

split_field_test() {
	local str
	local kd='>'
	local fd='|'
	local fields

	str="${fd}aaa${kd}111${fd}bbb${kd}222${fd}ccc${kd}333${fd}"
	split_field "${fd}" "${str}" fields

	echo "${FUNCNAME[0]}:${LINENO}: '${str}' = '${fields[@]}'" >&2

	local field
	for field in "${fields[@]}"; do
		local k
		local v

		split_kv "${kd}" "${field}" k v
		echo "${FUNCNAME[0]}:${LINENO}: '${field}' = '${k}' + '${v}'" >&2
	done

	str="${fd}this${kd}should${fd}${fd}fail${fd}"
	split_field "${fd}" "${str}" fields
}

delimiter_check() {
	local value="${1}"

	if [[ "${value}" == *${fld_delimiter}* ]]; then
		echo "[${line_no}:${card_number}] ERROR: Bad value '${fld_delimiter}': '${value}'" >&2
		exit 1
	fi

	if [[ "${value}" == *${kv_delimiter}* ]]; then
		echo "[${line_no}:${card_number}] ERROR: Bad value '${kv_delimiter}': '${value}'" >&2
		exit 2
	fi

	if [[ "${value}" == *${val_tag}* ]]; then
		echo "[${line_no}:${card_number}] ERROR: Bad value '${val_tag}': '${value}'" >&2
		exit 3
	fi
}

read_file() {
	local in_vcard
	local line_no=0
	local card_number=0
	local card_data
	local line_in

	unset in_vcard
	while read -r line_in; do
		((line_no += 1))

		line_in="$(remove_dos_eol "${line_in}")"

		if [[ ! "${line_in}" ]]; then
			[[ ${verbose} ]] && echo "[${line_no}] skip: '${line_in}'" >&2
			continue
		fi

		if [[ ! ${in_vcard} ]]; then
			if [[ "${line_in}" != "BEGIN:VCARD" ]]; then
				echo "[${line_no}] ERROR: Bad vcard start: '${line_in}'" >&2
				exit 2
			fi

			((card_number += 1))
			[[ ${verbose} ]] && echo "[${line_no}:${card_number}] Start vcard" >&2
			in_vcard=1
			card_data="CARD_NO${kv_delimiter}${card_number}"
			card_data+="${fld_delimiter}VERSION${kv_delimiter}${val_tag}VERSION${val_tag}"
			card_data+="${fld_delimiter}FN${kv_delimiter}${val_tag}FN${val_tag}"
			card_data+="${fld_delimiter}N${kv_delimiter}${val_tag}N${val_tag}"
		else
			if [[ "${line_in}" == "END:VCARD" ]]; then
				[[ ${verbose} ]] && echo "[${line_no}:${card_number}] '${card_data}'" >&2
				[[ ${verbose} ]] && echo "[${line_no}:${card_number}] End vcard" >&2
				[[ ${verbose} ]] && echo "" >&2

				unset in_vcard
				cards+=("${card_data}")
			else
				local regex="^[[:space:]]*([[:graph:]]*):([[:print:]]*)$"

				if [[ ! "${line_in}" =~ ${regex} ]]; then
					echo "[${line_no}:${card_number}] ERROR: Match failed: '${line_in}'" >&2
					exit 3
				fi

				local key
				local value

				key="${BASH_REMATCH[1]}"
				value="${BASH_REMATCH[2]}"

				[[ ${verbose} ]] && echo "[${line_no}:${card_number}] '${line_in}' => '${key}' + '${value}'" >&2

				delimiter_check "${key}"
				delimiter_check "${value}"

				if [[ "${card_data}" == *${val_tag}${key}${val_tag}* ]]; then
					card_data="${card_data/${val_tag}${key}${val_tag}/${value}}"
				else
					card_data+="${fld_delimiter}${key}${kv_delimiter}${value}"
				fi
			fi
		fi
	done < "${in_file}"
}

echo_array() {
	local str="${1}"
	local card

	echo "card count = ${#cards[@]}" >&2
	for card in "${cards[@]}"; do
		echo "${str}: '${card}'" >&2
	done
	echo "" >&2
}

for_each_card() {
	local card_start_callback=${1}
	local kv_callback=${2}
	local card_end_callback=${3}
	local -n _for_each_card__cards=${4}

	local idx
	local card

	IFS=$'\n'
	for idx in ${!_for_each_card__cards[@]}; do
		card=${_for_each_card__cards[${idx}]}

		${card_start_callback} "${card}" _for_each_card__cards ${idx}
		local fields
		split_field "${fld_delimiter}" "${card}" fields
		for field in "${fields[@]}"; do
			local key
			local value
			split_kv "${kv_delimiter}" "${field}" key value
			#[[ ${verbose} ]] && echo " field: '${field}' = '${key}' + '${value}'" >&2
			${kv_callback} "${key}" "${value}" _for_each_card__cards ${idx}
		done
		${card_end_callback} "${card}" _for_each_card__cards ${idx}
	done
	unset IFS
}

empty_callback() {
	return 0
}

clean_numbers() {
	cn_kv_callback() {
		local key="${1}"
		local value="${2}"
		local -n _cn_kv_callback__cards=${3}
		local idx=${4}

		if [[ "${key}" == TEL* ]]; then
			local old_number="${value}"

			# Strip '+' from country code.
			# +1-123-456-7890 -> 123-456-7890
			if [[ "${value:0:1}" == "+" ]]; then
				value="${value:1}"
			fi
			
			# Strip US country code.
			# 1-123-456-7890  -> 123-456-7890
			if [[ "${value:0:2}" == "1-" ]]; then
				value="${value:2}"
			fi

			# Add dashes to US number.
			# 1234567890      -> 123-456-7890
			if [[ ${#value} -eq 10 ]]; then
				if [[ "${value:3:1}" != "-" \
					&& "${value:6:1}" != "-" ]]; then
					value="${value::6}-${value:6}"
					value="${value::3}-${value:3}"
				fi

			fi

			# Add dashes to IDD + Japan number.
			# 01181123456789  -> 011-81-123-45-6789
			if [[ ${#value} -eq 14 && "${value:0:5}" == "01181" ]]; then
				value="${value::10}-${value:10}"
				value="${value::8}-${value:8}"
				value="${value::5}-${value:5}"
				value="${value::3}-${value:3}"
			fi

			# Add IDD and dashes to Japan number.
			# 81123456789  -> 011-81-123-45-6789
			if [[ ${#value} -eq 11 && "${value:0:2}" == "81" ]]; then
				value="${value::7}-${value:7}"
				value="${value::5}-${value:5}"
				value="${value::2}-${value:2}"
				value="011-${value}"
			fi

			# Add IDD to Japan number.
			# 81-123-45-6789  -> 011-81-123-45-6789
			if [[ ${#value} -eq 14 && "${value:0:3}" == "81-" ]]; then
				value="011-${value}"
			fi
			
			if [[ "${value}" != "${old_number}" ]]; then
				local old_card="${_cn_kv_callback__cards[idx]}"

				_cn_kv_callback__cards[idx]="${_cn_kv_callback__cards[idx]/${old_number}/${value}}"

				if [[ ${debug} ]]; then
					# echo "TEL:  '${old_number}' -> '${value}'" >&2
					echo "${FUNCNAME[0]}: old: '${old_card}'" >&2
					echo "${FUNCNAME[0]}: new: '${_cn_kv_callback__cards[idx]}'" >&2
					echo "" >&2
				fi
			fi
		fi
		return 0
	}

	for_each_card \
		empty_callback \
		cn_kv_callback \
		empty_callback \
		cards
}

remove_dupes() {
	rd_card_start_callback() {
		local card="${1}"
		local -n _rd_card_start_callback__cards=${2}
		local idx=${3}

		local regex="^CARD_NO[${kv_delimiter}][[:digit:]]*[${fld_delimiter}]([[:print:]]*)$"

		if [[ ! "${card}" =~ ${regex} ]]; then
			echo "${FUNCNAME[0]}: ERROR: Match failed: '${card}'" >&2
			exit 1
		fi

		local card_data="${BASH_REMATCH[1]}"

		if [[ "${card_data}" == "${previous_card_data}" ]]; then
			[[ ${debug} ]] && echo "${FUNCNAME[0]}: dupe:   '${card_data}'" >&2
			unset _rd_card_start_callback__cards[idx]
		else
			[[ ${debug} ]] && echo "${FUNCNAME[0]}: unique: '${card_data}'" >&2
		fi
		previous_card_data="${card_data}"
	}

	local previous_card_data

	unset previous_card_data
	for_each_card \
		rd_card_start_callback \
		empty_callback \
		empty_callback \
		cards
}

combine_cards() {
	cc_kv_callback() {
		local key="${1}"
		local value="${2}"
		local -n _cc_kv_callback__cards=${3}
		local idx=${4}

		if [[ "${key}" == "FN" ]]; then
			local card="${_cc_kv_callback__cards[idx]}"
			local name="${value}"
			local regex="[${fld_delimiter}](TEL;[[:print:]]+)$"

			if [[ ! "${card}" =~ ${regex} ]]; then
				echo "${FUNCNAME[0]}: WARNING: Match failed, no TEL: '${card}'" >&2
				previous=()
				return 0
			fi

			local tel_data="${BASH_REMATCH[1]}"

			if [[ "${name}" == "${previous[name]}" ]]; then
				if [[ ${debug} ]]; then
					echo "${FUNCNAME[0]}: dupe:   '${name}'" >&2
					echo "idx:      '${idx}'" >&2
					echo "name:     '${name}'" >&2
					echo "tel_data: '${tel_data}'" >&2
					echo "previous[idx]:      '${previous[idx]}'" >&2
					echo "previous[name]:     '${previous[name]}'" >&2
					echo "previous[tel_data]: '${previous[tel_data]}'" >&2
					echo "" >&2
				fi

				unset "_cc_kv_callback__cards[${previous[idx]}]"
				_cc_kv_callback__cards[${idx}]+="${fld_delimiter}${previous[tel_data]}"

				previous[idx]="${idx}"
				previous[name]="${name}"
				previous[tel_data]+="${fld_delimiter}${tel_data}"
			else
				if [[ ${debug} ]]; then
					echo "${FUNCNAME[0]}: unique: '${name}'" >&2
					echo "idx:      '${idx}'" >&2
					echo "name:     '${name}'" >&2
					echo "tel_data: '${tel_data}'" >&2
					echo "" >&2
				fi
				previous[idx]="${idx}"
				previous[name]="${name}"
				previous[tel_data]="${tel_data}"
			fi
		fi
		return 0
	}

	declare -A previous
	previous=()

	for_each_card \
		empty_callback \
		cc_kv_callback \
		empty_callback \
		cards
}

print_cards() {
	pc_card_start_callback() {
		local card="${1}"
		#echo "${FUNCNAME[0]}: '${card}'" >&2
		echo -e "BEGIN:VCARD\r" >> "${out_file}"
	}

	pc_card_end_callback() {
		local card="${1}"
		#echo "${FUNCNAME[0]}: '${card}'" >&2
		echo -e "END:VCARD\r" >> "${out_file}"
	}

	pc_kv_callback() {
		local key="${1}"
		local value="${2}"
		local value_extra

		#echo "${FUNCNAME[0]}: '${key}' + '${value}'" >&2
		case "${key}" in
		CARD_NO)
			return
			;;
		FN)
			if [[ "${value}" == "${previous_name}" ]]; then
				((dupe_number += 1))
				value_extra=" dupe#${dupe_number}"
			else
				dupe_number=0
				unset value_extra
			fi
			previous_name="${value}"
			;;
		*)
			;;
		esac
		echo -e "${key}:${value}${value_extra}\r" >> "${out_file}"
		return 0
	}


	echo -n '' > "${out_file}"

	local previous_name
	local dupe_number

	unset previous_name
	dupe_number=0
	for_each_card \
		pc_card_start_callback \
		pc_kv_callback \
		pc_card_end_callback \
		cards
}

#===============================================================================
export PS4='\[\e[0;33m\]+ ${BASH_SOURCE##*/}:${LINENO}:(${FUNCNAME[0]:-"?"}):\[\e[0m\] '
script_name="${0##*/}"

trap "on_exit 'Failed.'" EXIT
set -o pipefail
set -e

#split_kv_test; exit
#split_field_test; exit

process_opts "${@}"

if [[ ! ${in_file} || "${in_file}" == '-' ]]; then
	in_file='/dev/stdin'
fi

if [[ ! ${out_file} && "${in_file}" == '/dev/stdin' ]] \
	|| [[ "${out_file}" == '-' ]]; then
	out_file="/dev/stdout"
fi

if [[ ! ${out_file} ]]; then
	out_file="${in_file%.*}.out"
fi

if [[ "${step_sort}${step_clean_numbers}${step_remove_dupes}${step_combine_cards}" == "" ]]; then
	step_sort=1
	step_clean_numbers=1
	step_remove_dupes=1
	step_combine_cards=1
fi

if [[ ${usage} ]]; then
	usage
	trap - EXIT
	exit 0
fi

if [[ -f "${in_file}" ]]; then
	type="$(file -b ${in_file})"
	if [[ "${type##vCard visiting card, version 2.1*}" ]]; then
		echo "${script_name}: WARNING: Input file: '${in_file}' is type '${type}'" >&2
	fi
fi

if [[ "${in_file}" == '/dev/stdin' ]]; then
	echo "${script_name}: INFO: Waiting for input on stdin..." >&2
fi

declare -a cards
fld_delimiter='|'
kv_delimiter='>'
val_tag='!'

read_file
[[ ${debug} ]] && echo_array "cards"

if [[ ${step_sort} ]]; then
	IFS=$'\n'
	cards=($(sort -t ${fld_delimiter} -k 3 <<<"${cards[*]}"))
	unset IFS
	[[ ${debug} ]] && echo_array "sorted"
fi

if [[ ${step_clean_numbers} ]]; then
	clean_numbers
	[[ ${debug} ]] && echo_array "clean_numbers"
fi

if [[ ${step_remove_dupes} ]]; then
	remove_dupes
	[[ ${debug} ]] && echo_array "remove_dupes"
fi

if [[ ${step_combine_cards} ]]; then
	combine_cards
	[[ ${debug} ]] && echo_array "combine_cards"
fi

print_cards

trap "on_exit 'Success.'" EXIT
exit 0
