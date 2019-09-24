#!/bin/bash

# Parse and verify the parameters
for param in "$@"; do
	case ${param} in
		--profile=*)
			PROFILE=${param#--profile=}
			;;
		--token=*)
			MFA_TOKEN_CODE=${param#--token=}
			;;
		--duration=*)
		  DURATION=${param#--duration=}
			;;
	  --dry-run)
      DRY_RUN=1
    ;;
		*)
		  UNKNOWN_PARAM="${param}"
			echo Unknown Params "$UNKNOWN_PARAM"
			echo Script usage "get-session-token.sh --profile=prod --token=123456"
			exit 1
			;;
	esac
done

is_dry_run() {
  if [ -z "$DRY_RUN" ]; then
    return 1
  else
    return 0
  fi
}

set_vars() {
	AWS_CLI=$(command -v aws)
  if [ -z "$AWS_CLI" ]; then
  echo "aws cli is not installed"
  exit 1
  fi
	JQ=$(command -v jq)
	if [ -z "$JQ" ]; then
	echo "jq is not installed"
	exit 1
	fi
  ST_PROFILE=st-$PROFILE
	if [ -z "$PROFILE" ]; then
		PROFILE=default
		ST_PROFILE=st
	fi
	DEF_DURATION=3600
	if [ -z "$DURATION" ]; then
		DURATION=$DEF_DURATION
	fi
	executor='sh -c'
  if is_dry_run; then
    executor="echo"
  fi
	echo "setup account \"$PROFILE\" for \"$DURATION\" seconts"
}

get_mfa_device() {
	if ! MFA_DEVICE_DATA=$(aws iam list-mfa-devices --profile "$ST_PROFILE") ; then
  echo "Cant get mfa device"
  exit 1
  fi
	MFA_DEVICE=$(jq -r '.MFADevices[].SerialNumber' <<< "$MFA_DEVICE_DATA")
	if [[ $MFA_DEVICE =~ arn:aws:iam:: ]] ; then
		echo Using MFA_DEVICE "$MFA_DEVICE"
	else
	  echo "$MFA_DEVICE_DATA"
		exit 1
	fi
}

setup_account() {
	if ! AWS_SESSION_DATA=$(aws --profile $ST_PROFILE sts get-session-token --duration "$DURATION" --serial-number "$MFA_DEVICE" --token-code "$MFA_TOKEN_CODE") ; then
	echo "Cant get session data"
	exit 1
	fi
	eval "$(jq -r '.Credentials | to_entries | .[] | .key + "=\"" + .value + "\""' <<< "$AWS_SESSION_DATA")"
	$executor "aws --profile $PROFILE configure set aws_access_key_id \"${AccessKeyId}\""
  $executor "aws --profile $PROFILE configure set aws_secret_access_key \"${SecretAccessKey}\""
  $executor "aws --profile $PROFILE configure set aws_session_token \"${SessionToken}\""
}

main() {
	set_vars
  get_mfa_device
	setup_account
}

main
